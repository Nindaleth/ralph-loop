#!/bin/bash
# Spinner module for ralph.sh
# Animated spinner display with step tracking
# Dependencies: constants.sh, timing.sh, terminal.sh

# Spinner characters
SPINNER='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
SPINNER_PID=""
CURRENT_STEP="Thinking"

# Spinner function - runs in background, reads step from STEP_FILE
# Usage: start_spinner; do_work; stop_spinner
start_spinner() {
  echo "Thinking" > "$STEP_FILE"
  echo "" > "$PREVIEW_LINE_FILE"

  (
    # Spinner chars as array for proper unicode handling
    local -a SPIN_CHARS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local i=0
    local spin_len=${#SPIN_CHARS[@]}
    local term_width preview_max
    while true; do
      term_width=$(get_terminal_width)
      # The preview prefix uses six columns; keep the last column empty.
      preview_max=$((term_width - 7))
      local step=$(cat "$STEP_FILE" 2>/dev/null || echo "Thinking")
      local preview=$(cat "$PREVIEW_LINE_FILE" 2>/dev/null || echo "")
      local char="${SPIN_CHARS[$i]}"
      # Line 1: spinner + step, Line 2: dimmed preview
      printf '\r\033[K'
      if [ "$term_width" -gt 4 ]; then
        step=$(truncate_line "$step" "$((term_width - 5))")
        printf "  ${C}%s${R} %s" "$char" "$step"
      fi
      printf '\n\r\033[K'
      if [ -n "$preview" ] && [ "$preview_max" -gt 0 ]; then
        preview=$(truncate_line "$preview" "$preview_max")
        printf "    ${D}\xe2\x96\xb8 %s${R}" "$preview"
      fi
      printf '\033[A\r'
      i=$(( (i + 1) % spin_len ))
      sleep 0.1
    done
  ) &
  SPINNER_PID=$!
}

# Stop the spinner
stop_spinner() {
  if [ -n "$SPINNER_PID" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    # Clear both lines (spinner and preview)
    printf "\r\033[K\n\033[K\033[A\r"
  fi
  SPINNER_PID=""
}

# Update spinner step based on output line and record step timing
update_spinner_step() {
  local line="$1"
  local detected=$(detect_step "$line")
  if [ -n "$detected" ]; then
    echo "$detected" > "$STEP_FILE"

    # Clean step name (remove trailing spaces) for timing tracking
    local clean_step=$(echo "$detected" | LC_ALL=C sed 's/ *$//' 2>/dev/null)

    # Record timing if step changed
    if [ "$clean_step" != "$CURRENT_STEP_NAME" ]; then
      record_step_time "$clean_step"
    fi
  fi
}

# Update the preview line shown under the spinner
update_preview_line() {
  local line="$1"
  # Skip empty lines or lines that are just whitespace
  [ -z "$line" ] && return
  [[ "$line" =~ ^[[:space:]]*$ ]] && return
  # Sanitize: replace newlines/tabs with spaces, collapse multiple spaces
  # This prevents multi-line content from breaking cursor positioning
  line=$(echo "$line" | LC_ALL=C tr '\n\t\r' ' ' 2>/dev/null | LC_ALL=C sed 's/  */ /g; s/^ *//; s/ *$//' 2>/dev/null | head -1)
  # Skip if sanitization resulted in empty string
  [ -z "$line" ] && return
  # Write to preview file (spinner reads this)
  echo "$line" > "$PREVIEW_LINE_FILE"
}
