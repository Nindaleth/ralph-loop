import os
from pathlib import Path
import tempfile
import time
import unittest

from tests.support import bash_in, make_project


CID = "a" * 64


class RunDeadlineTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(dir="/tmp/opencode")
        self.addCleanup(tmp.cleanup)
        self.base = Path(tmp.name)
        self.project = make_project(self.base, [{"id": "TASK-1", "passes": False}])
        (self.base / "bin").mkdir()
        self.calls = self.base / "calls"
        docker = self.base / "bin/docker"
        docker.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$CALLS"\n')
        docker.chmod(0o755)
        self.env = {"HOME": str(self.base), "CALLS": str(self.calls),
                    "PATH": f"{self.base / 'bin'}:{os.environ['PATH']}"}

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


if __name__ == "__main__":
    unittest.main()
