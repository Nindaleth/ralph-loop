import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from tests.support import ROOT, event


class OpenCodeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir="/tmp/opencode")
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.env = {**os.environ, "HOME": str(self.base), "TERM": "dumb"}

    def bash(self, code, **env):
        return subprocess.run(["bash", "-c", code], cwd=ROOT, text=True,
                              capture_output=True, timeout=20,
                              env={**self.env, **env})

    def test_only_final_finished_assistant_text_supplies_promises(self):
        """Wrapper echoes and tool output were accepted as COMPLETE."""
        complete = "<promise>COMPLETE</promise>"
        text = event("text", text="Done " + complete)
        end = event("step_finish", reason="stop")
        cases = [
            ([text, end], "Done " + complete),
            ([complete, event("tool_use", text=complete),
              event("reasoning", text=complete)], ""),
            ([text, event("step_finish", reason="tool-calls")], ""),
            ([text, end, event("step_start", "msg_next"),
              event("text", "msg_next", text="Still working"),
              event("step_finish", "msg_next", reason="stop")], "Still working"),
            ([text, end, event("step_start", "msg_next")], ""),
            ([text, event("step_finish", reason="length")], ""),
            ([text, end, json.dumps({"type": "error", "error": {"message": "failed"}})], ""),
        ]
        for lines, expected in cases:
            with self.subTest(lines=lines):
                path = self.base / "events"
                path.write_text("\n".join(lines) + "\n")
                result = self.bash('source scripts/lib/output.sh; '
                                   'extract_final_summary "$EVENTS"',
                                   RALPH_AGENT="opencode", EVENTS=str(path))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

    def test_loop_uses_wrapper_and_rejects_failed_or_echoed_completion(self):
        """Linux script invocation failed and wait status was discarded."""
        project = self.base / "project with spaces"
        project.mkdir()
        shutil.copy(ROOT / "ralph.sh", project)
        shutil.copytree(ROOT / "scripts/lib", project / "scripts/lib")
        (project / ".agent/logs").mkdir(parents=True)
        (project / ".agent/tasks.json").write_text('[{"id":"TASK-1","passes":false}]')
        prompt = "Quotes ' \" $HOME `false`\n<promise>COMPLETE</promise>"
        (project / ".agent/PROMPT.md").write_text(prompt)
        subprocess.run(["git", "init", "-q", str(project)], check=True)
        (self.base / "bin").mkdir()
        (self.base / "bin/ocd.sh").write_text(
            'if [ "$3" = session ]; then\n'
            '  printf "%s\\0" "$@" > "$EXPORT_CAPTURE"\n'
            '  cat "$EXPORT_EVENTS"\n  return "$EXPORT_EXIT"\nfi\n'
            'printf "%s\\0" "$@" > "$CAPTURE"\n'
            'printf "%s\\n" "$OCD_QUIET" "$OCD_CIDFILE" > "$CONTEXT"\n'
            'cat "$EVENTS"\nreturn "$CHILD_EXIT"\n')
        complete = event("text", text="<promise>COMPLETE</promise>")
        finish = event("step_finish", reason="stop")
        def exported(text, **changes):
            message = {"id": "msg_final", "type": "assistant", "finish": "stop",
                       "time": {"created": 2, "completed": 3},
                       "content": [{"type": "text", "text": text}], **changes}
            return json.dumps({"info": {"id": "ses_test"}, "messages": [
                {"id": "msg_user", "type": "user", "text": prompt},
                {"id": "msg_earlier", "type": "assistant", "finish": "tool-calls",
                 "time": {"created": 1, "completed": 2},
                 "content": [{"type": "text", "text": "<promise>COMPLETE</promise>"}]},
                message]}, indent=2)

        for output, status, export, export_exit, expected in [
            (complete + "\n" + finish, "7", "", "0", 7),
            ("Adding these entrypoint arguments: " + prompt, "0", "", "0", 1),
            (complete + "\n" + finish, "0", "", "0", 0),
            (complete, "0", exported("<promise>COMPLETE</promise>"), "0", 0),
            (complete, "0", exported("<promise>BLOCKED:missing access</promise>"), "0", 2),
            (complete, "0", exported("<promise>DECIDE:choose backend</promise>"), "0", 3),
            (complete, "0", exported("Still working", finish="tool-calls"), "0", 1),
            (complete, "0", exported("<promise>COMPLETE</promise>",
                                    time={"created": 2}), "0", 1),
            (complete, "0", "Export failed", "7", 7),
        ]:
            with self.subTest(status=status, output=output):
                events = self.base / "events"
                events.write_text(output + "\n")
                (self.base / "export-events").write_text(export + "\n")
                result = subprocess.run(
                    ["bash", "ralph.sh", "--agent", "opencode", "--once",
                     "--", "--model", "provider/model#variant with spaces"],
                    cwd=project, capture_output=True, text=True, timeout=20,
                    env={**self.env, "EVENTS": str(events), "CHILD_EXIT": status,
                          "CAPTURE": str(self.base / "argv"),
                          "EXPORT_EVENTS": str(self.base / "export-events"),
                          "EXPORT_EXIT": export_exit,
                          "EXPORT_CAPTURE": str(self.base / "export-argv"),
                          "CONTEXT": str(self.base / "context")})
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                args = (self.base / "argv").read_bytes().decode().split("\0")[:-1]
                self.assertEqual(args, [str(self.base / ".opencode/bin/opencodedev"),
                                       "--standalone", "run", "--agent", "ralph-build",
                                       "--yolo", "--format", "json", "--model",
                                       "provider/model#variant with spaces",
                                       f"PROJECT_ROOT={project}\n\n{prompt}"])
                self.assertEqual((self.base / "context").read_text().splitlines()[0], "1")
                self.assertTrue(list((project / ".agent/history").glob("ITERATION-*.txt")))
                if export:
                    export_args = (self.base / "export-argv").read_bytes().decode().split("\0")[:-1]
                    self.assertEqual(export_args, [str(self.base / ".opencode/bin/opencodedev"),
                                                  "--standalone", "session", "export", "ses_test"])

    def test_cleanup_stops_only_captured_container(self):
        """Killing the wrapper client must not leave its private server running."""
        binaries = self.base / "bin"
        binaries.mkdir()
        docker = binaries / "docker"
        docker.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$CALLS"\n')
        docker.chmod(0o755)
        cid = self.base / "container.cid"
        cid.write_text("a" * 64 + "\n")
        result = self.bash('source scripts/lib/cleanup.sh; cleanup; cleanup',
                           PATH=f"{binaries}:{os.environ['PATH']}",
                           RALPH_AGENT="opencode", RALPH_CONTAINER_CIDFILE=str(cid),
                           CALLS=str(self.base / "calls"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.base / "calls").read_text().splitlines(),
                         ["container stop --time 5 " + "a" * 64])


if __name__ == "__main__":
    unittest.main()
