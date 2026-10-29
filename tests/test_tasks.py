from pathlib import Path
import tempfile
import unittest

from tests.support import bash_in, make_project


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


if __name__ == "__main__":
    unittest.main()
