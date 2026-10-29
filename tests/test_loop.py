import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

from tests.support import CID, GIT_ENV, event, git, install_fakes, make_project, tasks_of

BUDGET = json.dumps({"type": "error", "timestamp": 1, "sessionID": "ses_test", "error": {
    "name": "APIError", "data": {"message": "Your organization or enterprise has "
                                 "exceeded its Copilot budget. Contact your admin."}}})

# Runs $SCRIPTS/call-N.sh (or call-default.sh) for the Nth agent call.
SCRIPTED_OCD = f'''printf %s {CID} > "$OCD_CIDFILE"
if [ "$3" = session ]; then echo '{{"info":{{"id":"ses_test"}},"messages":[]}}'; return 0; fi
n=$(( $(cat "$SCRIPTS/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$SCRIPTS/count"
printf %s "${{@: -1}}" > "$SCRIPTS/prompt-$n"
script="$SCRIPTS/call-$n.sh"
[ -f "$script" ] || script="$SCRIPTS/call-default.sh"
bash "$script"
return $?
'''

QUESTION = 'Use A < B?\nOr "C" \\ D?'

# Rejects commits that touch nothing but the tasks file.
TASKS_ONLY_HOOK = "#!/bin/sh\ngit diff --cached --name-only | grep -qvx .agent/tasks.json\n"


def said(text):
    return "\n".join([event("step_start"), event("text", text=text),
                      event("step_finish", reason="stop")])


def call(action):
    """Shell body for one fake builder run, from a short action phrase."""
    words = action.split()
    body, status = [], 0
    if words[0] == "finish":
        task = words[1]
        body += [f"echo done > {task}.txt",
                 f"jq '(.[] | select(.id == \"{task}\") | .passes) = true' .agent/tasks.json"
                 " > t.json && mv t.json .agent/tasks.json",
                 f"git add {task}.txt .agent/tasks.json && git commit -qm 'feat: {task}'"]
        text = f"<promise>{task}:DONE</promise>"
        if "exit" in words:
            status = int(words[-1])
    elif words[0] == "decide":
        text = f"<promise>DECIDE:{QUESTION}</promise>"
    elif words[0] == "break":
        body.append("printf '[{' > .agent/tasks.json && git commit -qam 'oops'")
        text = "Nothing to do."
    elif words[0] == "budget_error":
        body.append('touch "${STARTED:-/dev/null}"')
        if len(words) > 1:
            body.append(f"sleep {words[1]}")
        return "\n".join(body + [f"cat <<'EOF'\n{BUDGET}\nEOF", "exit 1"]) + "\n"
    elif words[0] == "no_docker":
        return "echo 'ocd.sh: line 35: docker: command not found'\nexit 127\n"
    else:
        text = "Nothing to do."
    return "\n".join(body + [f"cat <<'EOF'\n{said(text)}\nEOF", f"exit {status}"]) + "\n"


def T(i, passes=False, deps=None):
    task = {"id": f"TASK-{i}", "passes": passes}
    if deps:
        task["dependencies"] = deps
    return task


class LoopTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(dir="/tmp/opencode")
        self.addCleanup(tmp.cleanup)
        self.base = Path(tmp.name)
        self.project = make_project(self.base, [{"id": "TASK-1", "passes": False}])
        self.env = {**os.environ, "TERM": "dumb", **GIT_ENV, **install_fakes(self.base)}
        self.calls = Path(self.env["CALLS"])

    def wait_for(self, path, limit=20):
        deadline = time.monotonic() + limit
        while not path.exists():
            self.assertLess(time.monotonic(), deadline, f"{path} never appeared")
            time.sleep(0.1)

    def test_sigterm_mid_run_stops_container_and_writes_summary(self):
        started = self.base / "started"
        (self.base / "bin/ocd.sh").write_text(
            f'printf %s {CID} > "$OCD_CIDFILE"\n'
            'touch "$STARTED"\n'
            'sleep 60\n')
        proc = subprocess.Popen(["bash", "ralph.sh", "--agent", "opencode"],
                                cwd=self.project, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True,
                                env={**self.env, "STARTED": str(started)})
        self.addCleanup(proc.kill)
        self.wait_for(started)

        proc.send_signal(signal.SIGTERM)
        output, _ = proc.communicate(timeout=20)

        self.assertEqual(proc.returncode, 143, output)
        self.assertIn(f"container stop --time 5 {CID}", self.calls.read_text())
        summaries = list((self.project / ".agent/history").glob("SUMMARY-*.txt"))
        self.assertEqual(len(summaries), 1, output)
        self.assertIn("SIGTERM", summaries[0].read_text())

    def scripted_ralph(self, project, calls, *args, **env):
        scripts = self.base / "scripts"
        shutil.rmtree(scripts, ignore_errors=True)
        scripts.mkdir()
        for n, action in enumerate(calls, 1):
            (scripts / f"call-{n}.sh").write_text(call(action))
        if calls:
            (scripts / "call-default.sh").write_text(call(calls[-1]))
        (self.base / "bin/ocd.sh").write_text(SCRIPTED_OCD)
        env = {**self.env, **GIT_ENV, "RALPH_WAIT_UNIT": "0",
               "SCRIPTS": str(scripts), **env}
        return scripts, env, ["bash", "ralph.sh", "--agent", "opencode", *args]

    def test_loop_outcomes_end_to_end(self):
        cases = [
            # an environment failure does not use the run budget
            ("budget error then progress", [T(1)], ["budget_error", "finish TASK-1"],
             ["-n", "1"], 0, ["TASK-1", "TASK-1"]),
            ("stalls", [T(1)], ["noop", "noop", "noop"], ["-n", "10"], 6,
             ["TASK-1"] * 3),
            ("progress then crash", [T(1)], ["finish TASK-1 exit 7"], ["-n", "1"], 0,
             ["TASK-1"]),
            ("foundation decide", [T(1), T(2)], ["decide"], [], 3, ["TASK-1"]),
            ("park and route around", [T(1, True), T(2), T(3, deps=["TASK-2"]), T(4)],
             ["decide", "finish TASK-4"], [], 8, ["TASK-2", "TASK-4"]),
            # a missing docker binary is never transient
            ("docker missing on the first run", [T(1)], ["no_docker"], [], 4, ["TASK-1"]),
            ("builder commits a broken tasks file", [T(1)], ["break", "finish TASK-1"],
             ["-n", "2"], 0, ["TASK-1", "TASK-1"]),
            ("hook rejects bookkeeping commits", [T(1, True), T(2)], ["decide"], [], 8,
             ["TASK-2"]),
        ]
        for name, tasks, calls, args, code, prompted in cases:
            with self.subTest(name):
                base = self.base / name.replace(" ", "-")
                base.mkdir()
                project = make_project(base, tasks)
                if name == "hook rejects bookkeeping commits":
                    hook = project / ".git/hooks/pre-commit"
                    hook.write_text(TASKS_ONLY_HOOK)
                    hook.chmod(0o755)
                scripts, env, argv = self.scripted_ralph(project, calls, *args)
                result = subprocess.run(argv, cwd=project, env=env, capture_output=True,
                                        text=True, timeout=60)
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, code, output)
                self.assertEqual((scripts / "count").read_text().strip(),
                                 str(len(prompted)), output)
                for n, task in enumerate(prompted, 1):
                    self.assertRegex((scripts / f"prompt-{n}").read_text(), rf"Do {task}\b")
                if name == "park and route around":
                    git(project, "rev-parse", "--verify", "ralph/parked/TASK-2")
                    self.assertEqual(tasks_of(project)[1]["parked"]["reason"], QUESTION)

    def test_outage_gives_up_after_max_outage(self):
        scripts, env, argv = self.scripted_ralph(
            self.project, ["budget_error 1"], "--max-outage", "2s")
        result = subprocess.run(argv, cwd=self.project, env=env, capture_output=True,
                                text=True, timeout=60)
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)

    def test_sigterm_during_environment_wait_exits_promptly(self):
        started = self.base / "started"
        scripts, env, argv = self.scripted_ralph(
            self.project, ["budget_error"], RALPH_WAIT_UNIT="600", STARTED=str(started))
        proc = subprocess.Popen(argv, cwd=self.project, env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.addCleanup(proc.kill)
        self.wait_for(started)
        history = self.project / ".agent/history"
        deadline = time.monotonic() + 20
        while not list(history.glob("ITERATION-*-1.txt")):
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.1)
        time.sleep(0.5)

        sent = time.monotonic()
        proc.send_signal(signal.SIGTERM)
        output, _ = proc.communicate(timeout=10)

        self.assertEqual(proc.returncode, 143, output)
        self.assertLess(time.monotonic() - sent, 10)
        self.assertTrue(list(history.glob("SUMMARY-*.txt")), output)


if __name__ == "__main__":
    unittest.main()
