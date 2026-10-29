#!/bin/bash
# Progress module for ralph.sh
# Decides from git, tasks.json and the project check whether a run finished its task
# Dependencies: tasks.sh, check.sh

# Return 0 when the run made progress on task_id, 1 when it did not, 2 when
# the check could not start and 3 when the bookkeeping commit failed.
# Sets PROGRESS_DETAIL to the first condition that failed.
# Usage: evaluate_progress <task_id> <base_sha> <passes_before>
evaluate_progress() {
  local task_id="$1" base="$2" before="$3" after others check_status=0
  after=$(passes_snapshot)
  if ! jq -e --arg id "$task_id" '.[$id] == true' <<<"$after" >/dev/null; then
    PROGRESS_DETAIL="$task_id not marked passing"
    return 1
  fi
  others=$(jq -rn --arg id "$task_id" --argjson b "$before" --argjson a "$after" \
    '[$a | keys_unsorted[] | select(. != $id and $a[.] != ($b[.] // false))] | join(" ")')
  if [ -n "$others" ]; then
    PROGRESS_DETAIL="passes changed on other tasks: $others"
    return 1
  fi
  if [ "$(git rev-parse HEAD)" = "$base" ]; then
    PROGRESS_DETAIL="no new commit"
    return 1
  fi
  if check_is_active; then
    run_project_check || check_status=$?
    if [ "$check_status" -ne 0 ]; then
      PROGRESS_DETAIL="$CHECK_DETAIL"
      return "$check_status"
    fi
  fi
  PROGRESS_DETAIL="$task_id done"
  if ! commit_bookkeeping "chore(ralph): record $task_id passes"; then
    PROGRESS_DETAIL="cannot commit $TASKS_FILE"
    return 3
  fi
}

# Put every passes value back to its pre-run state and commit that.
# Usage: revert_run_passes <task_id> <passes_before> <reason>
revert_run_passes() {
  local task_id="$1" before="$2" reason="$3"
  restore_passes "$before" &&
    commit_bookkeeping "chore(ralph): revert $task_id passes, $reason"
}
