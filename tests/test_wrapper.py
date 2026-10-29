import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


WRAPPER = Path("/home/liskar/bin/ocd.sh")


@unittest.skipUnless(WRAPPER.is_file(), "personal ocd.sh is not installed")
class WrapperTests(unittest.TestCase):
    def test_quiet_wrapper_keeps_errors_and_exact_container_arguments(self):
        """Wrapper argument diagnostics could falsely finish the loop."""
        with tempfile.TemporaryDirectory(dir="/tmp/opencode") as directory:
            home = Path(directory)
            repo = home / "project"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(["git", "-C", str(repo), "config", "alias.root",
                            "rev-parse --show-toplevel"], check=True)
            cache = home / ".cache/opencode"
            cache.mkdir(parents=True)
            (cache / "ocd_alias_md5").write_text(hashlib.md5(WRAPPER.read_bytes()).hexdigest())
            binaries = home / "bin"
            binaries.mkdir()
            docker = binaries / "docker"
            docker.write_text(
                '#!/usr/bin/env python3\nimport json, os, pathlib, sys\n'
                'args = sys.argv[1:]\n'
                'if args[0] == "build":\n'
                ' print("simulated build failure", file=sys.stderr)\n'
                ' sys.exit(7)\n'
                'if args[:2] == ["container", "run"]:\n'
                ' pathlib.Path(os.environ["CAPTURE"]).write_text(json.dumps(args))\n'
                ' print("MODEL_OUTPUT")\n')
            docker.chmod(0o755)
            host = binaries / "host"
            host.write_text('#!/bin/bash\necho "$2 has address 127.0.0.1"\n')
            host.chmod(0o755)
            env = {**os.environ, "HOME": directory, "HOSTNAME": "test-host",
                   "PATH": f"{binaries}:{os.environ['PATH']}", "OCD_QUIET": "1",
                   "OCD_CIDFILE": str(home / "container.cid"),
                   "CAPTURE": str(home / "argv"), "WRAPPER": str(WRAPPER)}
            prompt = "<promise>COMPLETE</promise> ' \"\nnext line"
            result = subprocess.run(
                ["bash", "-c", 'source "$WRAPPER" "$@"', "bash",
                 str(home / ".opencode/bin/opencodedev"), "--standalone", "run", prompt],
                cwd=repo, env=env, text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "MODEL_OUTPUT")
            self.assertNotIn(prompt, result.stdout + result.stderr)
            args = json.loads((home / "argv").read_text())
            self.assertEqual(args[args.index("--cidfile") + 1], env["OCD_CIDFILE"])
            self.assertEqual(args[-4:], ["localhost/opencode:wrapper", "--standalone", "run", prompt])
            refused = subprocess.run(["bash", "-c", 'source "$WRAPPER"'],
                                     cwd=home, env=env, text=True,
                                     capture_output=True, timeout=20)
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn("refusing", refused.stderr)
            (cache / "ocd_alias_md5").write_text("force rebuild")
            failed = subprocess.run(["bash", "-c", 'source "$WRAPPER" upstream'],
                                    cwd=repo, env=env, text=True,
                                    capture_output=True, timeout=20)
            self.assertEqual(failed.returncode, 7)
            self.assertIn("simulated build failure", failed.stderr)


if __name__ == "__main__":
    unittest.main()
