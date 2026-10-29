import json
from pathlib import Path
import tempfile
import unittest

from tests.support import bash_in, git, install_fakes, make_project, tasks_of


def T(i, passes=False, deps=None, **kw):
    return {"id": f"TASK-{i}", "passes": passes, "priority": 100 - i,
            "dependencies": deps, **kw}


class TaskSelectionTests(unittest.TestCase):
    def project(self, tasks, check=None):
        tmp = tempfile.TemporaryDirectory(dir="/tmp/opencode")
        self.addCleanup(tmp.cleanup)
        return make_project(Path(tmp.name), tasks, check)

    def run_fn(self, project, code):
        result = bash_in(project, code)
        return result.returncode, result.stdout.strip(), result.stderr

    def test_next_task_follows_array_order_dependencies_and_parking(self):
        cases = [
            ([T(1, True), T(2), T(3)], "TASK-2", None),
            ([T(1), T(2, deps=["TASK-3"]), T(3)], "TASK-1", None),
            ([T(1, True), T(2, deps=["TASK-3"]), T(3)], "TASK-3", None),
            ([T(1, True), T(2, parked={"kind": "DECIDE"}), T(3, deps=["TASK-2"]),
              T(4, deps=["TASK-3"])], "", "3"),
            ([{"id": "TASK-1", "passes": False}], "TASK-1", None),
            ([T(1, True)], "", "0"),
        ]
        for tasks, expected, remaining in cases:
            with self.subTest(tasks=tasks):
                project = self.project(tasks)
                rc, out, err = self.run_fn(project, "next_task_id")
                self.assertEqual((rc, out), (0, expected), err)
                if remaining is not None:
                    _, count, _ = self.run_fn(project, "remaining_task_count")
                    self.assertEqual(count, remaining)

    def test_validation_errors_and_warnings(self):
        check = {"command": "true", "enabled_by": "TASK-1"}
        cases = [
            ([T(1, deps=["TASK-9"])], check, 1, "TASK-9"),
            ([T(1)], {"command": "true", "enabled_by": "TASK-9"}, 1, "TASK-9"),
            ([T(1, deps=["TASK-2"]), T(2)], check, 0, "Warning"),
            ([T(1)], None, 0, "check.json"),
        ]
        for tasks, chk, code, text in cases:
            with self.subTest(tasks=tasks, check=chk):
                rc, _, err = self.run_fn(self.project(tasks, chk), "validate_tasks")
                self.assertEqual(rc, code, err)
                self.assertIn(text, err)

    def test_foundation_is_tasks_up_to_gate(self):
        tasks = [T(i) for i in range(1, 6)]
        check = {"command": "true", "enabled_by": "TASK-3"}
        _, out, err = self.run_fn(self.project(tasks, check), "foundation_task_ids")
        self.assertEqual(out.split(), ["TASK-1", "TASK-2", "TASK-3"], err)
        _, out, err = self.run_fn(self.project(tasks), "foundation_task_ids")
        self.assertEqual(out.split(), ["TASK-1"], err)


class ProgressTests(unittest.TestCase):
    def builder(self, project, flips, commit):
        tasks = tasks_of(project)
        for task in tasks:
            if task["id"] in flips:
                task["passes"] = True
            if task["id"] == "TASK-2":
                task["notes"] = "x"
        (project / ".agent/tasks.json").write_text(json.dumps(tasks, indent=2) + "\n")
        if commit == "all":
            git(project, "commit", "-q", "-am", "feat: builder work")
        elif commit == "other":
            (project / "src.txt").write_text("code\n")
            git(project, "add", "src.txt")
            git(project, "commit", "-q", "-m", "feat: builder code")

    def test_progress_requires_own_flip_commit_and_green_check(self):
        cases = [
            ("flip TASK-2 + commit, check passes", ["TASK-2"], "all", "0", 0),
            ("flip TASK-2 uncommitted + commit other file", ["TASK-2"], "other", "0", 0),
            ("flip TASK-2 + TASK-3 + commit", ["TASK-2", "TASK-3"], "all", "0", 1),
            ("flip TASK-3 only + commit", ["TASK-3"], "all", "0", 1),
            ("flip TASK-2, no commit at all", ["TASK-2"], None, "0", 1),
            ("flip TASK-2 + commit, check fails", ["TASK-2"], "all", "3", 1),
        ]
        for name, flips, commit, check_exit, expected in cases:
            with self.subTest(name):
                tmp = tempfile.TemporaryDirectory(dir="/tmp/opencode")
                self.addCleanup(tmp.cleanup)
                base = Path(tmp.name)
                project = make_project(
                    base,
                    [{"id": "TASK-1", "passes": True}, {"id": "TASK-2", "passes": False},
                     {"id": "TASK-3", "passes": False}],
                    {"command": "exit $CHECK_EXIT", "enabled_by": "TASK-2"})
                env = {**install_fakes(base), "CHECK_EXIT": check_exit,
                       "SESSION_ID": "t", "ATTEMPT": "1", "CHECK_TIMEOUT": "20"}
                head = git(project, "rev-parse", "HEAD").strip()
                before = bash_in(project, "passes_snapshot").stdout.strip()
                self.builder(project, flips, commit)
                builder_head = git(project, "rev-parse", "HEAD").strip()
                result = bash_in(project,
                                 f"evaluate_progress TASK-2 {head} '{before}'; rc=$?; "
                                 f"echo \"rc=$rc;$PROGRESS_DETAIL\"; "
                                 f"[ $rc = 0 ] || revert_run_passes TASK-2 '{before}' 'not done'",
                                 env)
                self.assertIn(f"rc={expected};", result.stdout, result.stderr)
                self.assertEqual(git(project, "status", "--porcelain", "--", ".agent/tasks.json"), "")
                if expected == 1:
                    tasks = {t["id"]: t for t in tasks_of(project)}
                    self.assertEqual({k: v["passes"] for k, v in tasks.items()}, json.loads(before))
                    self.assertEqual(tasks["TASK-2"].get("notes"), "x")
                    self.assertIn(builder_head, git(project, "log", "--format=%H"))
                else:
                    self.assertTrue(tasks_of(project)[1]["passes"])


if __name__ == "__main__":
    unittest.main()
