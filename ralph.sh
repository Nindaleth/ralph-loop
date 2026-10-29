#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--help] [--once] [--max-iterations N] [N]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PRD_FILE="$SCRIPT_DIR/.agent/prd/PRD.md"
PROGRESS_FILE="$SCRIPT_DIR/.agent/logs/LOG.md"
HISTORY_DIR="$SCRIPT_DIR/.agent/history"

source "$SCRIPT_DIR/scripts/lib/constants.sh"
source "$SCRIPT_DIR/scripts/lib/logging.sh"
source "$SCRIPT_DIR/scripts/lib/preflight.sh"
source "$SCRIPT_DIR/scripts/lib/timing.sh"
source "$SCRIPT_DIR/scripts/lib/terminal.sh"
source "$SCRIPT_DIR/scripts/lib/spinner.sh"
source "$SCRIPT_DIR/scripts/lib/preview.sh"
source "$SCRIPT_DIR/scripts/lib/output.sh"
source "$SCRIPT_DIR/scripts/lib/cleanup.sh"
source "$SCRIPT_DIR/scripts/lib/promise.sh"
source "$SCRIPT_DIR/scripts/lib/notify.sh"
source "$SCRIPT_DIR/scripts/lib/agents.sh"
source "$SCRIPT_DIR/scripts/lib/display.sh"
source "$SCRIPT_DIR/scripts/lib/args.sh"
source "$SCRIPT_DIR/scripts/lib/execution.sh"

# Timing
START_TIME=$(date +%s)
ITERATION_TIMES=()
TOTAL_ITERATION_TIME=0
PREV_ITERATION_TIME=0

# Session ID for unique history file naming (YYYYMMDD-HHMMSS format). This is used to prevent overwrites between runs.
SESSION_ID=$(date +%Y%m%d-%H%M%S)

# Temporary files for spinner communication
STEP_FILE=$(mktemp)
PREVIEW_LINE_FILE=$(mktemp)

# Background process tracking for cleanup
AGENT_PID=""
OUTPUT_FILE=""
FULL_OUTPUT_FILE=""

# Set up traps
trap cleanup EXIT
trap handle_interrupt INT

# Parse arguments (sets MAX_ITERATIONS, ONCE_FLAG, RALPH_AGENT, AGENT_EXTRA_ARGS)
parse_arguments "$@"
RALPH_AGENT_NAME=$(agent_display_name "$RALPH_AGENT")
RALPH_SANDBOX_NAME=$(build_sandbox_name "$RALPH_AGENT" "$SCRIPT_DIR")

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Pre-flight checks
check_git_repo
check_agent_dependencies
check_required_files
check_history_dir
check_ansi_support

show_ralph
echo -e " ${C}Starting Ralph${R} ・ ${Y}v$VERSION${R} ・ Agent: ${Y}$RALPH_AGENT_NAME${R} ・ Sandbox: ${Y}$RALPH_SANDBOX_NAME${R} ・ Max iterations: ${Y}$MAX_ITERATIONS${R}"
echo ""

for i in $(seq 1 $MAX_ITERATIONS); do
  ITERATION_START=$(date +%s)

  # Initialize step timing for this iteration
  init_iteration_step_times

  echo -e "${B}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
  echo -e "  ↪ ${R}Iteration ${Y}$i${R} of ${Y}$MAX_ITERATIONS${R}"
  echo -e "${B}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
  echo -e ""

  # Run Agent with the ralph prompt (prepend PROJECT_ROOT)
  PROMPT_CONTENT="PROJECT_ROOT=$SCRIPT_DIR

$(cat "$SCRIPT_DIR/.agent/PROMPT.md")"

  # Start spinner
  start_spinner

  # Initialize rolling preview
  init_rolling_preview

  ATTEMPT=$i
  capture_agent_output
  if [ "$AGENT_EXIT_STATUS" -ne 0 ]; then
    stop_spinner
    clear_rolling_preview
    printf '\nAgent exited with status %s. Output saved to %s\n' \
      "$AGENT_EXIT_STATUS" "$HISTORY_FILE" >&2
    tail -n 15 "$HISTORY_FILE" >&2
    exit "$AGENT_EXIT_STATUS"
  fi
  if [ "$RESULT_RECOVERY_FAILED" = 1 ]; then
    stop_spinner
    clear_rolling_preview
    printf '\nCannot recover the OpenCode final result. Run output: %s\n' "$HISTORY_FILE" >&2
    tail -n 15 "$HISTORY_FILE" >&2
    exit "$RECOVERY_EXIT_STATUS"
  fi

  # Check for Docker daemon not ready error
  if echo "$OUTPUT" | grep -q "docker daemon not ready"; then
    stop_spinner
    clear_rolling_preview
    echo ""
    echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    echo -e "  ❌ ${RD}Docker Error${R}"
    echo -e "  Docker daemon is not ready. Please ensure Docker is running."
    echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    rm -f "$OUTPUT_FILE" "$FULL_OUTPUT_FILE"
    exit $EXIT_DOCKER_ERROR
  fi

  # Check for invalid API key / authentication error
  if echo "$OUTPUT" | grep -q "Invalid API key"; then
    stop_spinner
    clear_rolling_preview
    echo ""
    echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    echo -e "  ❌ ${RD}Authentication Error${R}"
    echo -e "  Invalid API key. Please authenticate inside the Docker sandbox."
    echo -e ""
    echo -e "  Run the following command and follow the login instructions:"
    echo -e "  ${C}$(agent_login_command "$RALPH_AGENT" "$RALPH_SANDBOX_NAME")${R}"
    echo -e "${RD}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    rm -f "$OUTPUT_FILE" "$FULL_OUTPUT_FILE"
    exit $EXIT_AUTH_ERROR
  fi

  if [ "$RALPH_AGENT" = "opencode" ]; then
    OUTPUT="$FINAL_SUMMARY"
  fi

  rm -f "$FULL_OUTPUT_FILE"
  FULL_OUTPUT_FILE=""  # Clear after removal

  # Stop spinner
  stop_spinner

  # Finalize step timing for this iteration (record time spent in last step)
  record_step_time ""

  # Clear rolling preview area to make room for summary
  clear_rolling_preview

  # Display the final summary (persists after iteration)
  if [ -n "$FINAL_SUMMARY" ]; then
    display_final_summary "$FINAL_SUMMARY" 10
  else
    # Fallback: show last 10 lines of parsed output if no result found
    FALLBACK_SUMMARY=$(echo "$OUTPUT" | tail -n 10)
    if [ -n "$FALLBACK_SUMMARY" ]; then
      display_final_summary "$FALLBACK_SUMMARY" 10
    fi
  fi

  # Clean up the raw output file (history file already saved)
  rm -f "$OUTPUT_FILE"
  OUTPUT_FILE=""  # Clear after removal

  # Calculate iteration duration
  ITERATION_END=$(date +%s)
  ITERATION_DURATION=$((ITERATION_END - ITERATION_START))
  ITERATION_TIMES+=($ITERATION_DURATION)
  TOTAL_ITERATION_TIME=$((TOTAL_ITERATION_TIME + ITERATION_DURATION))
  ITERATION_AVG=$((TOTAL_ITERATION_TIME / ${#ITERATION_TIMES[@]}))
  ITERATION_STR=$(format_duration $ITERATION_DURATION)
  AVG_STR=$(format_duration $ITERATION_AVG)
  DELTA_STR=$(format_delta $ITERATION_DURATION $PREV_ITERATION_TIME)
  PREV_ITERATION_TIME=$ITERATION_DURATION
  COMPLETED_TASK_IDS=$(format_completed_task_ids "$(printf '%s\n%s' "$OUTPUT" "$FINAL_SUMMARY")")
  TASK_IDS_SEGMENT=""
  if [ -n "$COMPLETED_TASK_IDS" ]; then
    TASK_IDS_SEGMENT=" ${C}│${R} Tasks: ${Y}$COMPLETED_TASK_IDS${R}"
  fi

  # Check for completion signal
  # Note: We check both $OUTPUT and $FINAL_SUMMARY because some agents emit
  # structured output where FINAL_SUMMARY has a cleaner final message.
  if has_complete_tag "$OUTPUT" || has_complete_tag "$FINAL_SUMMARY"; then
    ELAPSED=$(($(date +%s) - START_TIME))
    ELAPSED_STR=$(format_duration $ELAPSED)
    echo ""
    echo -e "${GR}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    echo -e "  🎉 ${GR}Ralph completed all tasks!${R}"
    echo -e "  ✅ Finished at iteration ${GR}$i${R} of ${GR}$MAX_ITERATIONS${R}"
    if [ -n "$DELTA_STR" ]; then
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    else
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    fi
    echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
    display_session_step_totals
    echo -e "${GR}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
    exit $EXIT_COMPLETE
  fi

  # Check for BLOCKED tag - agent needs human help
  # Check both $OUTPUT and $FINAL_SUMMARY (see completion signal comment above)
  if has_blocked_tag "$OUTPUT" || has_blocked_tag "$FINAL_SUMMARY"; then
    BLOCKED_REASON=$(extract_blocked_reason "$OUTPUT")
    # If not found in OUTPUT, try FINAL_SUMMARY
    [ -z "$BLOCKED_REASON" ] && BLOCKED_REASON=$(extract_blocked_reason "$FINAL_SUMMARY")
    ELAPSED=$(($(date +%s) - START_TIME))
    ELAPSED_STR=$(format_duration $ELAPSED)
    play_notification_sound
    show_notification "Ralph - BLOCKED" "$BLOCKED_REASON"
    display_blocked_message "$BLOCKED_REASON" "$i"
    if [ -n "$DELTA_STR" ]; then
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    else
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    fi
    echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
    display_session_step_totals
    exit $EXIT_BLOCKED
  fi

  # Check for DECIDE tag - agent needs human decision
  # Check both $OUTPUT and $FINAL_SUMMARY (see completion signal comment above)
  if has_decide_tag "$OUTPUT" || has_decide_tag "$FINAL_SUMMARY"; then
    DECIDE_QUESTION=$(extract_decide_question "$OUTPUT")
    # If not found in OUTPUT, try FINAL_SUMMARY
    [ -z "$DECIDE_QUESTION" ] && DECIDE_QUESTION=$(extract_decide_question "$FINAL_SUMMARY")
    ELAPSED=$(($(date +%s) - START_TIME))
    ELAPSED_STR=$(format_duration $ELAPSED)
    play_notification_sound
    show_notification "Ralph - Decision Needed" "$DECIDE_QUESTION"
    display_decide_message "$DECIDE_QUESTION" "$i"
    if [ -n "$DELTA_STR" ]; then
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    else
      echo -e "  ⏱️  Iteration $i: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R}$TASK_IDS_SEGMENT"
    fi
    echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
    display_session_step_totals
    exit $EXIT_DECIDE
  fi

  # Calculate elapsed time
  ELAPSED=$(($(date +%s) - START_TIME))
  ELAPSED_STR=$(format_duration $ELAPSED)

  if [ -n "$DELTA_STR" ]; then
    echo -e "${G}  └── ✓ Iteration $i complete${R}$TASK_IDS_SEGMENT ${C}│${R} Iteration: ${Y}$ITERATION_STR${R} ($DELTA_STR) ${C}│${R} Average: ${Y}$AVG_STR${R} ${C}│${R} Total: ${Y}$ELAPSED_STR${R}"
  else
    echo -e "${G}  └── ✓ Iteration $i complete${R}$TASK_IDS_SEGMENT ${C}│${R} Iteration: ${Y}$ITERATION_STR${R} ${C}│${R} Average: ${Y}$AVG_STR${R} ${C}│${R} Total: ${Y}$ELAPSED_STR${R}"
  fi

  # Display per-iteration step times
  STEP_TIMES_OUTPUT=$(format_step_times "ITERATION")
  if [ -n "$STEP_TIMES_OUTPUT" ]; then
    echo -e "${G}      └──${R} $STEP_TIMES_OUTPUT"
  fi
  sleep 2 || true
done

# Calculate final elapsed time
ELAPSED=$(($(date +%s) - START_TIME))
ELAPSED_STR=$(format_duration $ELAPSED)

# Calculate final average (if any iterations completed)
if [ ${#ITERATION_TIMES[@]} -gt 0 ]; then
  FINAL_AVG=$((TOTAL_ITERATION_TIME / ${#ITERATION_TIMES[@]}))
  FINAL_AVG_STR=$(format_duration $FINAL_AVG)
fi

echo ""
echo -e "${Y}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
echo -e "  ⚠️  ${Y}Ralph reached max iterations${R} (${M}$MAX_ITERATIONS${R})"
if [ ${#ITERATION_TIMES[@]} -gt 0 ]; then
  echo -e "  ⏱️  Average iteration time: ${Y}$FINAL_AVG_STR${R}"
fi
echo -e "  ⏱️  Total time: ${Y}$ELAPSED_STR${R}"
display_session_step_totals
echo -e "  📋 Check progress: ${G}$PROGRESS_FILE${R}"
echo -e "${Y}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
exit $EXIT_MAX_ITERATIONS
