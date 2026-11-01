#!/bin/bash
# Terminal module for ralph.sh
# ANSI support detection and terminal width utilities
# Dependencies: constants.sh

# Check if terminal supports ANSI escape sequences
check_ansi_support() {
  # Check if $TERM is set and not dumb
  if [ -z "$TERM" ] || [ "$TERM" = "dumb" ]; then
    ANSI_SUPPORTED=false
    return
  fi
  # Check for known terminal types that don't support ANSI
  case "$TERM" in
    dumb|unknown|network)
      ANSI_SUPPORTED=false
      return
      ;;
  esac
  # Check if stdout is a terminal
  if [ ! -t 1 ]; then
    ANSI_SUPPORTED=false
    return
  fi
  ANSI_SUPPORTED=true
}

# Get terminal width (default to 80 if unavailable)
get_terminal_width() {
  local size width
  # Background jobs have no terminal on stdin; COLUMNS can also be stale.
  if size=$(stty size 2>/dev/null < /dev/tty); then
    width=${size##* }
    if [[ "$width" =~ ^[1-9][0-9]*$ ]]; then
      printf '%s\n' "$width"
      return
    fi
  fi
  if width=$(tput cols 2>/dev/null) && [[ "$width" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' "$width"
    return
  fi
  echo "80"
}

# Truncate line to fit terminal width
truncate_line() {
  local LC_ALL=C.UTF-8
  local line="$1" max_width="$2"
  local length=${#line}
  local i char char_width width=0 prefix=""
  if [ "$max_width" -le 0 ]; then
    printf '\n'
    return
  fi
  for ((i = 0; i < length; i++)); do
    char=${line:i:1}
    case "$char" in
      [\ -~]) char_width=1 ;;
      # Non-ASCII characters may occupy two terminal columns.
      *) char_width=2 ;;
    esac
    width=$((width + char_width))
    if [ "$width" -gt "$max_width" ]; then
      if [ "$max_width" -lt 3 ]; then
        printf '%.*s\n' "$max_width" '...'
      else
        printf '%s...\n' "$prefix"
      fi
      return
    fi
    if [ "$width" -le $((max_width - 3)) ]; then
      prefix+="$char"
    fi
  done
  printf '%s\n' "$line"
}
