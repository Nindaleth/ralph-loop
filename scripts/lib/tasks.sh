#!/bin/bash
# Task index module for ralph.sh
# Reads .agent/tasks.json (a bare array) and .agent/check.json
# Dependencies: jq

TASKS_FILE="${TASKS_FILE:-.agent/tasks.json}"
CHECK_FILE="${CHECK_FILE:-.agent/check.json}"

# Print errors and warnings about tasks.json and check.json to stderr.
# Returns 1 when any error was found.
validate_tasks() {
  local gate="" problems
  if ! jq -e 'type == "array"' "$TASKS_FILE" >/dev/null 2>&1; then
    echo "Error: $TASKS_FILE is not a JSON array" >&2
    return 1
  fi
  if [ -f "$CHECK_FILE" ]; then
    gate=$(check_gate_task)
  else
    echo "Warning: $CHECK_FILE is missing, task completion is not checked by tests" >&2
  fi
  problems=$(jq -r --arg gate "$gate" '
    (map(.id)) as $ids
    | ([to_entries[] | {key: .value.id, value: .key}] | from_entries) as $pos
    | (if $gate != "" and ($ids | index($gate)) == null
       then "Error: enabled_by \($gate) in check.json is not a task" else empty end),
      (to_entries[] | .key as $i | .value as $t | ($t.dependencies // [])[]
       | if $pos[.] == null then "Error: \($t.id) depends on unknown task \(.)"
         elif $pos[.] > $i then "Warning: \($t.id) depends on \(.), which comes later in the list"
         else empty end)
  ' "$TASKS_FILE")
  [ -n "$problems" ] && printf '%s\n' "$problems" >&2
  ! grep -q '^Error:' <<< "$problems"
}

# Echo the task ID that activates the check, or nothing.
check_gate_task() {
  [ -f "$CHECK_FILE" ] || return 0
  jq -r '.enabled_by // empty' "$CHECK_FILE"
}

# Echo the foundation task IDs, one per line.
foundation_task_ids() {
  jq -r --arg gate "$(check_gate_task)" '
    if $gate == "" then .[0].id // empty
    else (map(.id) | index($gate)) as $end | .[0:($end // -1) + 1][].id end
  ' "$TASKS_FILE"
}

# Return 0 when every foundation task passes.
foundation_done() {
  local ids
  ids=$(foundation_task_ids | jq -Rsc 'split("\n") | map(select(. != ""))')
  jq -e --argjson ids "$ids" \
    '[.[] | select(.id as $id | $ids | index($id)) | .passes == true] | all' \
    "$TASKS_FILE" >/dev/null
}

# Echo the next runnable task ID, or nothing.
next_task_id() {
  jq -r '
    (map(select(.passes == true) | .id)) as $done
    | first(.[] | select(.passes != true and .parked == null
        and ((.dependencies // []) - $done | length) == 0) | .id) // empty
  ' "$TASKS_FILE"
}

# Echo how many tasks do not pass yet.
remaining_task_count() {
  jq -r 'map(select(.passes != true)) | length' "$TASKS_FILE"
}

# Echo every task's passes value as compact JSON.
passes_snapshot() {
  jq -c 'map({key: .id, value: (.passes == true)}) | from_entries' "$TASKS_FILE"
}
