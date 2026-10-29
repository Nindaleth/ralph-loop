#!/bin/bash
# Loop module for ralph.sh
# Runs one builder attempt on an assigned task and judges its outcome
# Dependencies: tasks.sh, progress.sh, outcome.sh, promise.sh, execution.sh,
#   spinner.sh, preview.sh, timing.sh, output.sh, display.sh, notify.sh, summary.sh

ENV_WAITS=(1 2 4 8 15)

# Usage: render_prompt <task_id> <note>
render_prompt() {
  local text
  text=$(cat "$SCRIPT_DIR/.agent/PROMPT.md")
  text=${text//"{{TASK_ID}}"/"$1"}
  text=${text//"{{PREVIOUS_RUN_NOTE}}"/"$2"}
  printf 'PROJECT_ROOT=%s\n\n%s' "$SCRIPT_DIR" "$text"
}

# Usage: previous_run_note <outcome> <detail>
previous_run_note() {
  case "$1" in
    progress|parked) ;;
    timeout)
      echo "The previous run on this task $2. The working tree may contain its partial edits." ;;
    *)
      echo "The previous run on this task did not count as done: $2. Look at git log and git diff before continuing." ;;
  esac
}

# Usage: env_wait_seconds <streak>
env_wait_seconds() {
  local index=$(( $1 < ${#ENV_WAITS[@]} ? $1 : ${#ENV_WAITS[@]} ))
  echo $(( ENV_WAITS[index - 1] * ${RALPH_WAIT_UNIT:-60} ))
}

# Usage: interruptible_sleep <seconds>
interruptible_sleep() {
  sleep "$1" >/dev/null 2>&1 &
  SLEEP_PID=$!
  wait "$SLEEP_PID" || true
  SLEEP_PID=""
}

# Echo the exit code for a first-attempt Docker or auth failure, or nothing.
preflight_failure_code() {
  [ "$ATTEMPT" = 1 ] || return 0
  if grep -qE "docker daemon not ready|docker: command not found" "$HISTORY_FILE" 2>/dev/null; then
    echo "$EXIT_DOCKER_ERROR"
  elif grep -q "Invalid API key" "$HISTORY_FILE" 2>/dev/null; then
    echo "$EXIT_AUTH_ERROR"
  fi
}

# Show the BLOCKED or DECIDE message and stop the loop.
# Usage: stop_for_help <BLOCKED|DECIDE> <text>
stop_for_help() {
  play_notification_sound
  if [ "$1" = BLOCKED ]; then
    show_notification "Ralph - BLOCKED" "$2"
    display_blocked_message "$2" "$ATTEMPT"
    stop_loop "BLOCKED on foundation task $TASK_ID: $2" "$EXIT_BLOCKED"
  fi
  show_notification "Ralph - Decision Needed" "$2"
  display_decide_message "$2" "$ATTEMPT"
  stop_loop "DECIDE on foundation task $TASK_ID: $2" "$EXIT_DECIDE"
}

# Read the help tag from the run's final message into RUN_TAG_KIND and RUN_TAG_TEXT.
read_run_tag() {
  RUN_TAG_KIND=""
  RUN_TAG_TEXT=""
  if has_blocked_tag "$FINAL_SUMMARY"; then
    RUN_TAG_KIND=BLOCKED
    RUN_TAG_TEXT=$(extract_blocked_reason "$FINAL_SUMMARY")
  elif has_decide_tag "$FINAL_SUMMARY"; then
    RUN_TAG_KIND=DECIDE
    RUN_TAG_TEXT=$(extract_decide_question "$FINAL_SUMMARY")
  elif has_retry_tag "$FINAL_SUMMARY"; then
    RUN_TAG_KIND=RETRY
    RUN_TAG_TEXT=$(extract_retry_reason "$FINAL_SUMMARY")
  fi
}

# Run the builder once on task_id and classify the run.
# Sets RUN_OUTCOME, RUN_DETAIL, RUN_TAG_KIND, RUN_TAG_TEXT, RUN_SECONDS,
# RUN_STARTED and RUN_BASE. Returns 1 when a bookkeeping commit fails.
# Usage: run_attempt <task_id> <note>
run_attempt() {
  local task_id="$1" before progress=0 env_failure=0 status=0
  RUN_OUTCOME=""
  RUN_BASE=$(git rev-parse HEAD)
  before=$(passes_snapshot)
  RUN_STARTED=$(date +%s)
  PROMPT_CONTENT=$(render_prompt "$task_id" "$2")

  init_iteration_step_times
  start_spinner
  init_rolling_preview
  capture_agent_output
  stop_spinner
  record_step_time ""
  clear_rolling_preview
  if [ -n "$FINAL_SUMMARY" ]; then
    display_final_summary "$FINAL_SUMMARY" 10
  fi
  rm -f "$OUTPUT_FILE" "$FULL_OUTPUT_FILE"
  OUTPUT_FILE=""
  FULL_OUTPUT_FILE=""

  read_run_tag
  if ! jq empty "$TASKS_FILE" 2> /dev/null; then
    git show "$RUN_BASE:$TASKS_FILE" > "$TASKS_FILE"
  fi
  if is_environment_failure "$HISTORY_FILE" "$AGENT_EXIT_STATUS" "$RESULT_RECOVERY_FAILED"; then
    env_failure=1
  fi
  evaluate_progress "$task_id" "$RUN_BASE" "$before" || status=$?
  case "$status" in
    0) progress=1 ;;
    2) env_failure=1; ENV_FAILURE_DETAIL="$PROGRESS_DETAIL" ;;
    3) RUN_DETAIL="$PROGRESS_DETAIL"; RUN_SECONDS=$(( $(date +%s) - RUN_STARTED )); return 1 ;;
  esac
  RUN_OUTCOME=$(classify_run "$progress" "$RUN_TAG_KIND" "$env_failure" \
    "$RUN_TIMED_OUT" "$AGENT_EXIT_STATUS")
  RUN_SECONDS=$(( $(date +%s) - RUN_STARTED ))

  case "$RUN_OUTCOME" in
    progress) RUN_DETAIL="$PROGRESS_DETAIL" ;;
    parked) RUN_DETAIL="$RUN_TAG_KIND: $RUN_TAG_TEXT" ;;
    environment)
      if [ "$RUN_TAG_KIND" = RETRY ] && [ "$env_failure" = 0 ]; then
        RUN_DETAIL="RETRY: $RUN_TAG_TEXT"
      else
        RUN_DETAIL="$ENV_FAILURE_DETAIL"
      fi ;;
    timeout) RUN_DETAIL="timed out after $(format_duration "$ITERATION_TIMEOUT")" ;;
    failure) RUN_DETAIL="agent exited $AGENT_EXIT_STATUS; $PROGRESS_DETAIL" ;;
    *) RUN_DETAIL="$PROGRESS_DETAIL" ;;
  esac
  if [ "$RUN_OUTCOME" != progress ] && [ "$RUN_OUTCOME" != parked ]; then
    revert_run_passes "$task_id" "$before" "$RUN_OUTCOME" || {
      RUN_DETAIL="cannot commit the passes revert for $task_id"
      return 1
    }
  fi
  RUN_BEFORE="$before"
}
