import json
from pathlib import Path
import tempfile
import time
import unittest

from tests.support import CID, bash_in, event, install_fakes, make_project


class RunDeadlineTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(dir="/tmp/opencode")
        self.addCleanup(tmp.cleanup)
        self.base = Path(tmp.name)
        self.project = make_project(self.base, [{"id": "TASK-1", "passes": False}])
        self.env = install_fakes(self.base)
        self.calls = Path(self.env["CALLS"])

    def test_timed_out_run_stops_its_container_and_returns(self):
        (self.base / "bin/ocd.sh").write_text(
            f'printf %s {CID} > "$OCD_CIDFILE"\n'
            'echo \'{"type":"step_start","sessionID":"ses_x","part":{}}\'\n'
            'exec sleep 60\n')
        started = time.monotonic()
        result = bash_in(self.project,
                         'ATTEMPT=1 ITERATION_TIMEOUT=1 RALPH_AGENT=opencode '
                         'SESSION_ID=t HISTORY_DIR=.agent/history '
                         'STEP_FILE=$(mktemp) PROMPT_CONTENT=x; '
                         'capture_agent_output; '
                         'echo "$RUN_TIMED_OUT $AGENT_EXIT_STATUS"', self.env)
        self.assertLess(time.monotonic() - started, 20)
        self.assertEqual(result.returncode, 0, result.stderr)
        timed_out, status = result.stdout.split()[-2:]
        self.assertEqual(timed_out, "1")
        self.assertNotEqual(status, "0")
        self.assertIn(f"container stop --time 5 {CID}", self.calls.read_text())

    def test_check_result_classes(self):
        (self.base / "bin/ocd.sh").write_text(
            'if [ -n "$CHECK_NO_START" ]; then echo "docker: daemon down"; return 125; fi\n'
            f'printf %s {CID} > "$OCD_CIDFILE"\n'
            'exec "$@"\n')
        cases = [
            ("true && exit 0", {}, 0),
            ("true && exit 3", {}, 1),
            ("sleep 60", {}, 1),
            ("true", {"CHECK_NO_START": "1"}, 2),
        ]
        check_file = self.project / ".agent/check.json"
        for command, extra, expected in cases:
            with self.subTest(command=command, extra=extra):
                self.calls.write_text("")
                check_file.write_text(json.dumps({"command": command, "enabled_by": "TASK-1"}))
                result = bash_in(self.project,
                                 'ATTEMPT=1 CHECK_TIMEOUT=1 SESSION_ID=t; '
                                 'run_project_check; echo "rc=$?; $CHECK_DETAIL"',
                                 {**self.env, **extra})
                self.assertIn(f"rc={expected};", result.stdout, result.stderr)
                if command == "sleep 60":
                    self.assertIn("container stop", self.calls.read_text())

    def test_environment_failure_detection(self):
        def err(message):
            return json.dumps({"type": "error", "error": {
                "name": "APIError", "data": {"message": message}}})
        started = event("step_start")
        budget = ("Your organization or enterprise has exceeded its Copilot budget. "
                  "Contact your admin to resume usage.")
        cases = [
            ([started, err(budget)], "1", "0", True, "Copilot budget"),
            ([started, err("429 Too Many Requests")], "1", "0", True, "429"),
            ([started, err("TypeError: x is undefined")], "1", "0", False, ""),
            (['Script started on 2026-10-29 22:05:33+01:00 [COMMAND="bash -c x"]',
              "docker: Error response from daemon: oops", "",
              'Script done on 2026-10-29 22:05:33+01:00 [COMMAND_EXIT_CODE="125"]'],
             "125", "0", True, "yes:docker: Error response from daemon: oops"),
            ([started, event("text", text="the network test failed")], "1", "0", False, ""),
        ]
        history = self.base / "history"
        for lines, status, recovery, expected, detail in cases:
            with self.subTest(lines=lines):
                history.write_text("\n".join(lines) + "\n")
                result = bash_in(self.project,
                                 f'if is_environment_failure "{history}" {status} {recovery}; '
                                 'then echo "yes:$ENV_FAILURE_DETAIL"; else echo no; fi')
                self.assertEqual(result.returncode, 0, result.stderr)
                if expected:
                    self.assertTrue(result.stdout.startswith("yes:"), result.stdout)
                    self.assertIn(detail, result.stdout)
                else:
                    self.assertEqual(result.stdout.strip(), "no")

    def test_first_matching_outcome_wins(self):
        cases = [
            (("1", "BLOCKED", "1", "1", "7"), "progress"),
            (("0", "DECIDE", "1", "1", "7"), "parked"),
            (("0", "RETRY", "0", "1", "0"), "environment"),
            (("0", "", "0", "1", "0"), "timeout"),
            (("0", "", "0", "0", "7"), "failure"),
            (("0", "", "0", "0", "0"), "no_progress"),
        ]
        for args, expected in cases:
            with self.subTest(args=args):
                quoted = " ".join(f'"{a}"' for a in args)
                result = bash_in(self.project, f"classify_run {quoted}")
                self.assertEqual((result.returncode, result.stdout.strip()),
                                 (0, expected), result.stderr)


if __name__ == "__main__":
    unittest.main()
