#!/bin/bash

# Start a command in a pseudo-TTY and expose its PID for cleanup.
start_agent_command() {
  local agent_command="$1" output_file="$2"
  if [ "$(uname -s)" = "Linux" ]; then
    export RALPH_AGENT_COMMAND="$agent_command"
    script -q -e -c 'bash -c "$RALPH_AGENT_COMMAND"' "$output_file" >/dev/null 2>>"$output_file" &
  else
    script -q -e "$output_file" bash -c "$agent_command" >/dev/null 2>>"$output_file" &
  fi
  AGENT_PID=$!
}

# Preserve the child status and stop its tracked container.
wait_agent_command() {
  if wait "$AGENT_PID"; then
    AGENT_EXIT_STATUS=0
  else
    AGENT_EXIT_STATUS=$?
  fi
  AGENT_PID=""
  stop_agent_container
}

# Recover completed projected output when the CLI omitted step_finish.
recover_opencode_result() {
  local session_id message_id command
  session_id=$(jq -Rnr '
    [inputs | fromjson? | select(type == "object")] |
    if any(.[]; .type == "error") then "" else
      [ .[] | select(.type == "text" or .type == "step_start" or
                      .type == "step_finish" or .type == "tool_use" or .type == "reasoning") |
        .sessionID | strings ] | unique |
      if length == 1 then .[0] else "" end
    end' "$OUTPUT_FILE")
  [[ "$session_id" =~ ^ses_[a-zA-Z0-9]+$ ]] || return 0
  message_id=$(jq -Rnr --arg session "$session_id" '
    [inputs | fromjson? | select(.sessionID == $session) |
     .part.messageID | strings] | last // ""' "$OUTPUT_FILE")
  [ -n "$message_id" ] || return 0
  export RALPH_SESSION_ID="$session_id"
  RALPH_CONTAINER_CIDFILE="$(mktemp -d)/container.cid"
  export RALPH_CONTAINER_CIDFILE
  command='export OCD_QUIET=1 OCD_CIDFILE="$RALPH_CONTAINER_CIDFILE"; source "$HOME/bin/ocd.sh" "$HOME/.opencode/bin/opencodedev" --standalone session export "$RALPH_SESSION_ID" | jq -Mc .; codes=("${PIPESTATUS[@]}"); if ((codes[0])); then exit "${codes[0]}"; else exit "${codes[1]}"; fi'
  local run_status="$AGENT_EXIT_STATUS"
  start_agent_command "$command" "$FULL_OUTPUT_FILE"
  wait_agent_command
  RECOVERY_EXIT_STATUS="$AGENT_EXIT_STATUS"
  AGENT_EXIT_STATUS="$run_status"
  if [ "$RECOVERY_EXIT_STATUS" -ne 0 ]; then
    tail -n 15 "$FULL_OUTPUT_FILE" >> "$HISTORY_FILE"
    RESULT_RECOVERY_FAILED=1
    return 0
  fi
  if ! FINAL_SUMMARY=$(extract_export_summary "$FULL_OUTPUT_FILE" "$session_id" "$message_id"); then
    RECOVERY_EXIT_STATUS=1
    RESULT_RECOVERY_FAILED=1
  fi
}

# Parse newly captured lines for the rolling preview.
read_agent_output() {
  local current_size line parsed
  current_size=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE")
  if [ "$current_size" -gt "$LAST_POS" ]; then
    while IFS= read -r line; do
      parsed=$(parse_json_content "$line")
      if [ -n "$parsed" ]; then
        printf '%s\n' "$parsed" >> "$FULL_OUTPUT_FILE"
        update_spinner_step "$parsed"
        update_preview_line "$parsed"
      fi
    done < <(tail -c +$((LAST_POS + 1)) "$OUTPUT_FILE")
    LAST_POS=$current_size
  fi
}

# Poll the agent until it ends or the deadline passes, running tick_command
# on every poll. Returns 124 after stopping a run that hit the deadline.
watch_agent_command() {
  local deadline="$1" tick_command="${2:-}"
  while kill -0 "$AGENT_PID" 2>/dev/null; do
    [ -z "$tick_command" ] || "$tick_command"
    if [ "$(date +%s)" -ge "$deadline" ]; then
      stop_agent_container
      stop_agent_process
      return 124
    fi
    sleep 0.2 || true
  done
  return 0
}

# Capture one agent invocation. Sets RUN_TIMED_OUT, AGENT_EXIT_STATUS,
# FINAL_SUMMARY, RESULT_RECOVERY_FAILED and HISTORY_FILE.
capture_agent_output() {
  RUN_TIMED_OUT=0
  RESULT_RECOVERY_FAILED=0
  RECOVERY_EXIT_STATUS=0
  FINAL_SUMMARY=""
  OUTPUT_FILE=$(mktemp)
  FULL_OUTPUT_FILE=$(mktemp)
  if [ "$RALPH_AGENT" = "opencode" ]; then
    RALPH_CONTAINER_CIDFILE="$(mktemp -d)/container.cid"
    export RALPH_CONTAINER_CIDFILE
  fi
  export PROMPT_CONTENT
  export DOCKER_DEFAULT_PLATFORM=linux/amd64

  local agent_command
  agent_command=$(build_agent_command "$RALPH_AGENT" "$RALPH_SANDBOX_NAME")
  start_agent_command "$agent_command" "$OUTPUT_FILE"
  LAST_POS=0
  if watch_agent_command $(( $(date +%s) + ITERATION_TIMEOUT )) read_agent_output; then
    read_agent_output
    wait_agent_command
  else
    RUN_TIMED_OUT=1
    AGENT_EXIT_STATUS=124
    read_agent_output
  fi
  OUTPUT=$(cat "$FULL_OUTPUT_FILE")
  HISTORY_FILE="$HISTORY_DIR/ITERATION-${SESSION_ID}-${ATTEMPT}.txt"
  strip_ansi_file "$OUTPUT_FILE" "$HISTORY_FILE"
  if [ "$AGENT_EXIT_STATUS" -ne 0 ] && [ "$RUN_TIMED_OUT" = 0 ]; then
    return 0
  fi
  FINAL_SUMMARY=$(extract_final_summary "$OUTPUT_FILE")
  if [ "$RALPH_AGENT" = "opencode" ] && [ -z "$FINAL_SUMMARY" ]; then
    recover_opencode_result
  fi
}
