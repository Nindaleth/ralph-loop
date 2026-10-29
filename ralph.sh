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
source "$SCRIPT_DIR/scripts/lib/summary.sh"
source "$SCRIPT_DIR/scripts/lib/tasks.sh"
source "$SCRIPT_DIR/scripts/lib/outcome.sh"
source "$SCRIPT_DIR/scripts/lib/check.sh"
source "$SCRIPT_DIR/scripts/lib/progress.sh"
source "$SCRIPT_DIR/scripts/lib/park.sh"
source "$SCRIPT_DIR/scripts/lib/loop.sh"

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
trap handle_terminate TERM

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
git rev-parse -q --verify HEAD >/dev/null || stop_loop "the repository has no commits yet" "$EXIT_SETUP_ERROR"
validate_tasks || stop_loop "invalid tasks.json" "$EXIT_SETUP_ERROR"

RUNS_USED=0
STALLS=0
ENV_STREAK=0
OUTAGE_START=0
ATTEMPT=0
NOTE=""

while true; do
  TASK_ID=$(next_task_id)
  if [ -z "$TASK_ID" ]; then
    if [ "$(remaining_task_count)" = 0 ]; then
      stop_loop "all tasks complete" "$EXIT_COMPLETE"
    fi
    stop_loop "every remaining task is parked or depends on a parked task" "$EXIT_ALL_PARKED"
  fi
  if [ "$RUNS_USED" -ge "$MAX_ITERATIONS" ]; then
    stop_loop "used all $MAX_ITERATIONS runs" "$EXIT_MAX_ITERATIONS"
  fi
  ATTEMPT=$((ATTEMPT + 1))
  FOUNDATION_WAS_DONE=0
  if foundation_done; then
    FOUNDATION_WAS_DONE=1
  fi

  echo -e "${B}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
  echo -e "  ↪ ${R}Run ${Y}$((RUNS_USED + 1))${R} of ${Y}$MAX_ITERATIONS${R} - ${Y}$TASK_ID${R} (attempt $ATTEMPT)"
  echo -e "${B}░░▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░${R}"
  echo ""

  if ! run_attempt "$TASK_ID" "$NOTE"; then
    record_run "$ATTEMPT" "$TASK_ID" "${RUN_OUTCOME:-error}" "${RUN_SECONDS:-0}" "$RUN_DETAIL"
    stop_loop "$RUN_DETAIL" "$EXIT_SETUP_ERROR"
  fi
  record_run "$ATTEMPT" "$TASK_ID" "$RUN_OUTCOME" "$RUN_SECONDS" "$RUN_DETAIL"
  echo -e "${G}  └── $RUN_OUTCOME${R} ${C}│${R} $TASK_ID ${C}│${R} ${Y}$(format_duration "$RUN_SECONDS")${R} ${C}│${R} $RUN_DETAIL"

  case "$RUN_OUTCOME" in
    progress)
      RUNS_USED=$((RUNS_USED + 1))
      STALLS=0
      ENV_STREAK=0
      NOTE=""
      ;;
    parked)
      if [ "$FOUNDATION_WAS_DONE" = 0 ]; then
        revert_run_passes "$TASK_ID" "$RUN_BEFORE" "$RUN_TAG_KIND" \
          || stop_loop "cannot commit the passes revert for $TASK_ID" "$EXIT_SETUP_ERROR"
        stop_for_help "$RUN_TAG_KIND" "$RUN_TAG_TEXT"
      fi
      park_run "$TASK_ID" "$RUN_TAG_KIND" "$RUN_TAG_TEXT" "$RUN_BASE" \
        || stop_loop "cannot park $TASK_ID" "$EXIT_SETUP_ERROR"
      echo -e "  Parked $TASK_ID on ${Y}$PARKED_BRANCH${R}"
      RUNS_USED=$((RUNS_USED + 1))
      ENV_STREAK=0
      NOTE=""
      ;;
    environment)
      PREFLIGHT_CODE=$(preflight_failure_code)
      if [ -n "$PREFLIGHT_CODE" ]; then
        stop_loop "first run could not start: $RUN_DETAIL" "$PREFLIGHT_CODE"
      fi
      ENV_STREAK=$((ENV_STREAK + 1))
      if [ "$ENV_STREAK" = 1 ]; then
        OUTAGE_START=$RUN_STARTED
      fi
      if [ $(( $(date +%s) - OUTAGE_START )) -ge "$MAX_OUTAGE" ]; then
        stop_loop "gave up after $(format_duration "$MAX_OUTAGE") of environment failures: $RUN_DETAIL" "$EXIT_OUTAGE"
      fi
      WAIT_SECONDS=$(env_wait_seconds "$ENV_STREAK")
      echo -e "  Environment failure, retrying $TASK_ID in ${Y}$(format_duration "$WAIT_SECONDS")${R}"
      interruptible_sleep "$WAIT_SECONDS"
      add_env_wait "$WAIT_SECONDS"
      ;;
    *)
      RUNS_USED=$((RUNS_USED + 1))
      STALLS=$((STALLS + 1))
      ENV_STREAK=0
      NOTE=$(previous_run_note "$RUN_OUTCOME" "$RUN_DETAIL")
      if [ "$STALLS" -ge "$MAX_STALLS" ]; then
        stop_loop "$STALLS runs in a row without progress" "$EXIT_MAX_STALLS"
      fi
      ;;
  esac
done
