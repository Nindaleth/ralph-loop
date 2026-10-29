import json
import os
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]

GIT_ENV = {
    "GIT_AUTHOR_NAME": "Ralph Test", "GIT_AUTHOR_EMAIL": "ralph@example.com",
    "GIT_COMMITTER_NAME": "Ralph Test", "GIT_COMMITTER_EMAIL": "ralph@example.com",
}


def event(kind, message="msg_final", **fields):
    return json.dumps({"type": kind, "timestamp": 1, "sessionID": "ses_test",
                       "part": {"messageID": message, **fields}})


def git(project, *args):
    return subprocess.run(["git", *args], cwd=project, text=True, check=True,
                          capture_output=True, env={**os.environ, **GIT_ENV}).stdout


def make_project(base, tasks, check=None,
                 prompt="Do {{TASK_ID}}\n{{PREVIOUS_RUN_NOTE}}"):
    project = Path(base) / "project"
    project.mkdir(parents=True)
    shutil.copy(ROOT / "ralph.sh", project)
    shutil.copytree(ROOT / "scripts/lib", project / "scripts/lib")
    agent = project / ".agent"
    (agent / "logs").mkdir(parents=True)
    (agent / "history").mkdir()
    (agent / "history/.gitignore").write_text("*\n!.gitignore\n")
    (agent / "tasks.json").write_text(json.dumps(tasks, indent=2) + "\n")
    (agent / "PROMPT.md").write_text(prompt)
    if check is not None:
        (agent / "check.json").write_text(json.dumps(check) + "\n")
    git(project, "init", "-q")
    git(project, "add", "-A")
    git(project, "commit", "-q", "-m", "init")
    return project


def bash_in(project, code, env=None):
    libs = "for f in scripts/lib/*.sh; do source \"$f\"; done\n"
    return subprocess.run(["bash", "-c", libs + code], cwd=project, text=True,
                          capture_output=True, timeout=30,
                          env={**os.environ, "TERM": "dumb", **GIT_ENV,
                               **(env or {})})


CID = "a" * 64

# Wrapper stand-in that records a container ID and runs the command locally.
LOCAL_OCD = f'printf %s {CID} > "$OCD_CIDFILE"\nexec "$@"\n'


def install_fakes(base, ocd_script=LOCAL_OCD):
    """Put a recording docker and the given ocd.sh under base/bin; return the env."""
    bin_dir = Path(base) / "bin"
    bin_dir.mkdir(exist_ok=True)
    docker = bin_dir / "docker"
    docker.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$CALLS"\n')
    docker.chmod(0o755)
    (bin_dir / "ocd.sh").write_text(ocd_script)
    return {"HOME": str(base), "CALLS": str(Path(base) / "calls"),
            "PATH": f"{bin_dir}:{os.environ['PATH']}"}


def tasks_of(project):
    return json.loads((Path(project) / ".agent/tasks.json").read_text())
