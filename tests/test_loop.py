import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

from tests.support import CID, install_fakes, make_project


class LoopTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(dir="/tmp/opencode")
        self.addCleanup(tmp.cleanup)
        self.base = Path(tmp.name)
        self.project = make_project(self.base, [{"id": "TASK-1", "passes": False}])
        self.env = {**os.environ, "TERM": "dumb", **install_fakes(self.base)}
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


if __name__ == "__main__":
    unittest.main()
