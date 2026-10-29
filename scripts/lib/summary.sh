#!/bin/bash
# Summary module for ralph.sh
# Records each run and prints what happened when the loop stops, however it stops
# Dependencies: timing.sh, tasks.sh

RUN_RECORDS=()
FINISHED_TASKS=()
ENV_WAIT_TOTAL=0
STOP_REASON=""
SUMMARY_PRINTED=0

# Usage: record_run <attempt> <task_id> <outcome> <seconds> <detail>
record_run() {
  RUN_RECORDS+=("$(printf '#%-3s %-10s %-12s %-9s %s' "$1" "$2" "$3" "$(format_duration "$4")" "$5")")
  if [ "$3" = "progress" ]; then
    FINISHED_TASKS+=("$2")
  fi
}

# Usage: add_env_wait <seconds>
add_env_wait() {
  ENV_WAIT_TOTAL=$((ENV_WAIT_TOTAL + $1))
}

# Usage: stop_loop <reason> <exit_code>
stop_loop() {
  STOP_REASON="$1"
  exit "$2"
}

# Print the parked tasks from tasks.json, one per line.
parked_task_lines() {
  local file="${TASKS_FILE:-.agent/tasks.json}"
  [ -f "$file" ] || return 0
  jq -r '.[]? | select(.parked) |
    "\(.id)  \(.parked.kind)  \(.parked.branch)\n    \(.parked.reason | gsub("\n"; "\n    "))"' \
    "$file" 2>/dev/null
}

summary_text() {
  local line parked
  echo "Ralph stopped: ${STOP_REASON:-interrupted}"
  echo ""
  echo "Runs:"
  if [ "${#RUN_RECORDS[@]}" -eq 0 ]; then
    echo "  (none finished)"
  fi
  for line in "${RUN_RECORDS[@]}"; do
    echo "  $line"
  done
  echo ""
  echo "Finished tasks: ${FINISHED_TASKS[*]:-none}"
  parked=$(parked_task_lines)
  echo "Parked tasks:${parked:+$'\n'}${parked:- none}" | sed '2,$s/^/  /'
  echo "Waiting on the environment: $(format_duration "$ENV_WAIT_TOTAL")"
}

# Print the summary once and keep a copy in the history directory.
print_summary() {
  if [ "$SUMMARY_PRINTED" = "1" ]; then
    return 0
  fi
  SUMMARY_PRINTED=1
  local file="${HISTORY_DIR:-.agent/history}/SUMMARY-${SESSION_ID}.txt"
  echo ""
  if [ -d "$(dirname "$file")" ]; then
    summary_text | tee "$file"
  else
    summary_text
  fi
}

handle_terminate() {
  STOP_REASON="terminated (SIGTERM)"
  exit 143
}
