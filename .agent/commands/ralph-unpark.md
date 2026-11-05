---
description: Unpark existing Ralph loop tasks parked on DECIDE/BLOCK
---

Unpark the currently parked tasks. Work in a separate git worktree off
main; do not commit or merge to main until I explicitly confirm - a
Ralph loop may be running.

For each task with a `parked` field in .agent/tasks.json:

1. Gather context, don't just repeat the stored question:
   - read the task definition and its dependencies' status
   - extract the builder's explanation and DECIDE/BLOCK question from
     .agent/history/ITERATION-*.txt (parse line by line, skip non-JSON,
     take part.text from type == "text" events; don't dump whole files)
   - inspect the parked branch named in `parked.branch` (diff vs. its
     base) for useful partial work
   - look at the relevant code/requirements (.agent/prd/REQUIREMENTS.md)
     so you can explain the actual problem
2. Present, per task:
   - what the builder was trying to do and where it got stuck
   - why it's a DECIDE vs. BLOCK (is it a judgment call or a real
     external blocker?)
   - 2-4 concrete options, with tradeoffs and your recommendation
   - whether the parked branch has work worth keeping
3. Stop and wait for my decisions. Ask all questions in one batch.

After I decide:
- remove only the `parked` field; leave `passes: false`; never mark
  dependencies complete to make a task runnable
- write my decision and any builder instructions into
  .agent/STEERING.md
- check that array order in tasks.json gives the intended priority
- don't run parking helpers, don't delete the parked branches
- show me the diff and wait for my OK before committing to main
