> ⛔ **YOUR TASK IS {{TASK_ID}}** — Complete only {{TASK_ID}}, commit, and STOP. Do NOT start another task. Do NOT use parallel agents.

{{PREVIOUS_RUN_NOTE}}

## Overview

You are implementing the project described in @.agent/prd/SUMMARY.md

## Required Setup

Run `npm run dev` (as background process) in `src` directory.
App will be running at http://localhost:3000

## Before Starting

Check @.agent/STEERING.md for critical work. Complete items in sequence, remove when done. Only proceed to implement tasks if no critical work pending.

## Task Flow

Your task is {{TASK_ID}}. Tasks are listed in @.agent/tasks.json

1. Read full spec: `.agent/tasks/{{TASK_ID}}.json`
2. Check existing dir structure in @.agent/STRUCTURE.md
3. Implement steps by step according to spec and write unit test
4. **UI tasks only:** do a Playwright smoke test
   - Check console for errors
   - Write minimal e2e test (happy path only)
   - Skip e2e if unit test already covers functionality
   - Save UI Screenshot to `.agent/screenshots/{{TASK_ID}}-{index}.png`, verify UI correctness. If debugging, use previous screenshots as reference.
5. Run `eslint --fix`, `prettier --write` and end to end tests for affected files.
6. Run `tsc` and unit tests project-wide
7. All tests must pass. Broke unrelated test? Fix it before proceeding.
8. When tests pass, set `passes: true` in `tasks.json` for {{TASK_ID}} only. Never change `passes` on any other task.
9. Log entry → `.agent/logs/LOG.md` (date, brief summary, screenshot path, newest at the top)
10. Update `.agent/STRUCTURE.md` if dirs changed. Exclude dotfiles, tests and config.
11. Commit using the Conventional Commit format. Stage only files that belong to {{TASK_ID}}, by name, plus the `tasks.json` flip and the log entry. Never run `git add -A` or `git add .`.

## Rules

- **CRITICAL**: Only work on {{TASK_ID}}. After committing it, you may output `<promise>{{TASK_ID}}:DONE</promise>`, then **STOP immediately**. Do NOT read the next task. Ralph checks your commit and `tasks.json` itself, so the tag is informational.
- Kill all background processes (dev server, etc.) before you finish.
- No git init/remote changes. **No git push**.
- Check the last 5 tasks in `.agent/logs/LOG.md` for past work

## Help Tags

Try solving the task yourself first.
When stuck after all possible solutions exhausted, output one of the following tags as the last thing in your final message:

1. **RETRY** — transient trouble that should go away on its own: network blips, service outages, a dev server that won't start because of the network. Ralph waits and gives the task to a fresh run. Output:

```
<promise>RETRY:brief description</promise>
```

2. **BLOCKED** — only for problems a human must fix. Output BLOCKED on first failure, without workarounds:

- Missing/invalid credentials or API keys
- `Blocked by network policy` → firewall, only user can change from host
- A broken dependency that cannot be installed or worked around
- Hardware/arch incompatibility with no known fix

```
<promise>BLOCKED:brief description</promise>
```

3. **DECIDE** — need human input: lib choices, architecture, unclear requirements, breaking changes. Output:

```
<promise>DECIDE:question (Option A vs B)</promise>
```

Ralph sets BLOCKED and DECIDE tasks aside for a human and continues with tasks that don't depend on them.
