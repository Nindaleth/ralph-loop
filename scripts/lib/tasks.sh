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
  problems=$(jq -r --arg gate "$gate" --arg stop "${STOP_BEFORE_TASK:-}" '
    (map(.id)) as $ids
    | ([to_entries[] | {key: .value.id, value: .key}] | from_entries) as $pos
    | (if $gate != "" and ($ids | index($gate)) == null
       then "Error: enabled_by \($gate) in check.json is not a task" else empty end),
      (if $stop != "" and ($ids | index($stop)) == null
       then "Error: --stop-before-task names unknown task \($stop)" else empty end),
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

# Echo the next runnable task ID before STOP_BEFORE_TASK, or nothing.
next_task_id() {
  jq -r --arg stop "${STOP_BEFORE_TASK:-}" '
    (map(select(.passes == true) | .id)) as $done
    | (if $stop == "" then length
       else (map(.id) | index($stop)) // error("unknown task \($stop)") end) as $end
    | first(.[0:$end][] | select(.passes != true and .parked == null
        and ((.dependencies // []) - $done | length) == 0) | .id) // empty
  ' "$TASKS_FILE"
}

# Print skip reasons before selected_id, or before the boundary/end when empty.
# Usage: skipped_task_lines <selected_id>
skipped_task_lines() {
  jq -r --arg selected "$1" --arg stop "${STOP_BEFORE_TASK:-}" '
    . as $tasks
    | (map({key: .id, value: .}) | from_entries) as $by_id
    | def unfinished_closure($frontier; $seen):
        ($frontier | map(select($by_id[.].passes != true)) - $seen | unique) as $new
        | if $new == [] then $seen
          else unfinished_closure(
            [$new[] | select($by_id[.].parked == null)
             | ($by_id[.].dependencies // [])[]]; $seen + $new)
          end;
      def reason($task):
        if $task.parked != null then
          {key: ["parked", $task.id],
           text: "parked (\($task.parked.kind // "unknown"))"}
        else
          unfinished_closure($task.dependencies // []; []) as $reachable
          | [$tasks[] | select(.parked != null and (.id as $id | $reachable | index($id)))
             | .id] as $parked
          | if $parked != [] then
              {key: ["parked-dependencies", $parked],
               text: "depend directly or transitively on parked \($parked | join(", "))"}
            else
              [($task.dependencies // [])[] | select($by_id[.].passes != true)] as $unmet
              | {key: ["unfinished-dependencies", ($unmet | sort)],
                 text: "unmet dependencies: \($unmet | join(", "))"}
            end
        end;
      def task_label($ids):
        if ($ids | length) == 1 then $ids[0]
        elif all($ids[]; test("^TASK-[0-9]+$"))
          and ([$ids[] | ltrimstr("TASK-") | tonumber] as $numbers
               | all(range(1; $numbers | length); $numbers[.] == $numbers[. - 1] + 1))
        then "\($ids[0]) to \($ids[-1])"
        else $ids | join(", ") end;
    (if $selected != "" then $selected else $stop end) as $limit
    | (if $limit == "" then length
       else (map(.id) | index($limit)) // error("unknown task \($limit)") end) as $end
    | reduce (.[0:$end] | to_entries[] | select(.value.passes != true)) as $entry
        ([];
         reason($entry.value) as $reason
         | if length > 0 and .[-1].key == $reason.key and .[-1].last + 1 == $entry.key then
             .[-1].ids += [$entry.value.id] | .[-1].last = $entry.key
           else . + [{ids: [$entry.value.id], last: $entry.key,
                      key: $reason.key, text: $reason.text}] end)
    | .[] | "Skipping \(task_label(.ids)): \(.text)"
  ' "$TASKS_FILE"
}

# Print task counts, parked tasks and the first five undone tasks in array order.
task_status() {
  local parked coming
  jq -r '(map(select(.passes == true) | .id)) as $done
    | "total: \(length)",
      "done: \($done | length)"' "$TASKS_FILE"
  parked=$(parked_task_lines)
  echo "parked:${parked:+$'\n'}${parked:- none}" | sed '2,$s/^/  /'
  coming=$(jq -r '[.[] | select(.passes != true) | .id] as $ids
    | ($ids[0:5][]),
      (if ($ids | length) > 5 then "...and \(($ids | length) - 5) more" else empty end)' "$TASKS_FILE")
  echo "coming up:"
  if [ -n "$coming" ]; then
    sed 's/^/  /' <<< "$coming"
  else
    echo "  none"
  fi
}

# Echo how many tasks do not pass yet.
remaining_task_count() {
  jq -r 'map(select(.passes != true)) | length' "$TASKS_FILE"
}

# Echo every task's passes value as compact JSON.
passes_snapshot() {
  jq -c 'map({key: .id, value: (.passes == true)}) | from_entries' "$TASKS_FILE"
}

# Set every task's passes to its value in snapshot_json, keeping all other fields.
restore_passes() {
  local snapshot="$1" restored
  jq -e --argjson snap "$(passes_snapshot)" '. == $snap' <<< "$snapshot" > /dev/null && return 0
  restored=$(jq --argjson snap "$snapshot" \
    'map(.id as $id | if ($snap | has($id)) then .passes = $snap[$id] else . end)' "$TASKS_FILE") || return 1
  printf '%s\n' "$restored" > "$TASKS_FILE"
}

# Commit only the tasks file, and only when it differs from HEAD.
commit_bookkeeping() {
  local message="$1"
  git diff --quiet HEAD -- "$TASKS_FILE" && return 0
  git commit -q --no-verify -m "$message" -- "$TASKS_FILE"
}

# Record why and where a task was parked.
# Usage: set_task_parked <task_id> <kind> <reason> <branch> <base_sha>
set_task_parked() {
  local updated
  updated=$(jq --arg id "$1" --arg kind "$2" --arg reason "$3" --arg branch "$4" --arg base "$5" \
    'map(if .id == $id then .parked = {kind: $kind, reason: $reason, branch: $branch, base: $base}
         else . end)' "$TASKS_FILE") || return 1
  printf '%s\n' "$updated" > "$TASKS_FILE"
}
