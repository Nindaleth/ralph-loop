#!/bin/bash
# Project check module for ralph.sh
# Runs the project's own check command in a fresh wrapper container
# Dependencies: tasks.sh, execution.sh, cleanup.sh, timing.sh, output.sh

# Echo the check command from the check file, or nothing.
check_command() {
  [ -f "$CHECK_FILE" ] || return 0
  jq -r '.command // empty' "$CHECK_FILE"
}

# Return 0 when the check file exists and its gate task passes.
check_is_active() {
  local gate
  gate=$(check_gate_task)
  [ -n "$gate" ] || return 1
  jq -e --arg gate "$gate" 'any(.[]; .id == $gate and .passes == true)' \
    "$TASKS_FILE" >/dev/null
}

# Run the check command with CHECK_TIMEOUT as its deadline.
# Returns 0 on pass, 1 on failure or timeout, 2 when the container never started.
# Sets CHECK_DETAIL and writes the output to CHECK-<session>-<attempt>.txt.
run_project_check() {
  local output_file history_file started=0 status run_status="${AGENT_EXIT_STATUS:-0}"
  local command='export OCD_QUIET=1 OCD_CIDFILE="$RALPH_CONTAINER_CIDFILE"; source "$HOME/bin/ocd.sh" /bin/bash -lc "$RALPH_CHECK_COMMAND"'
  RALPH_CHECK_COMMAND=$(check_command)
  export RALPH_CHECK_COMMAND
  RALPH_CONTAINER_CIDFILE="$(mktemp -d)/container.cid"
  export RALPH_CONTAINER_CIDFILE
  output_file=$(mktemp)
  history_file="${HISTORY_DIR:-.agent/history}/CHECK-${SESSION_ID}-${ATTEMPT}.txt"

  start_agent_command "$command" "$output_file"
  if ! watch_agent_command $(( $(date +%s) + CHECK_TIMEOUT )); then
    status=124
  else
    [ -s "$RALPH_CONTAINER_CIDFILE" ] && started=1
    wait_agent_command
    status="$AGENT_EXIT_STATUS"
  fi
  AGENT_EXIT_STATUS="$run_status"
  strip_ansi_file "$output_file" "$history_file"
  rm -f "$output_file"

  if [ "$status" = 124 ]; then
    CHECK_DETAIL="check timed out after $(format_duration "$CHECK_TIMEOUT")"
    return 1
  elif [ "$status" = 125 ] || [ "$started" = 0 ]; then
    CHECK_DETAIL="check container did not start: $(grep -v '^[[:space:]]*$' "$history_file" | tail -n 1)"
    return 2
  elif [ "$status" != 0 ]; then
    CHECK_DETAIL="check exited $status"
    return 1
  fi
  CHECK_DETAIL="check passed"
  return 0
}
