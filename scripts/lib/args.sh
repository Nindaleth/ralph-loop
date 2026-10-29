#!/bin/bash
# Arguments module for ralph.sh
# CLI argument parsing
# Dependencies: constants.sh, agents.sh

# Echo a duration in seconds. Accepts 90, 90s, 30m and 3h.
parse_duration() {
  local text="$1"
  if [[ "$text" =~ ^([0-9]+)([smh]?)$ ]]; then
    case "${BASH_REMATCH[2]}" in
      h) echo $(( BASH_REMATCH[1] * 3600 )) ;;
      m) echo $(( BASH_REMATCH[1] * 60 )) ;;
      *) echo "${BASH_REMATCH[1]}" ;;
    esac
  else
    echo "Error: invalid duration '$text', use for example 90s, 30m or 3h" >&2
    return 1
  fi
}

# Echo the value of an option given as "--opt value" or "--opt=value".
option_value() {
  local option="$1" value="$2"
  if [ -z "$value" ]; then
    echo "Error: ${option%%=*} requires a value" >&2
    return 1
  fi
  echo "$value"
}

# Parse command line arguments
# Sets: MAX_ITERATIONS, ONCE_FLAG, RALPH_AGENT, AGENT_EXTRA_ARGS,
#       MAX_STALLS, and ITERATION_TIMEOUT, MAX_OUTAGE, CHECK_TIMEOUT in seconds
# Usage: parse_arguments "$@"
parse_arguments() {
  MAX_ITERATIONS=10
  ONCE_FLAG=false
  RALPH_AGENT="claude"
  AGENT_EXTRA_ARGS=()
  MAX_STALLS=3
  ITERATION_TIMEOUT=1800
  MAX_OUTAGE=10800
  CHECK_TIMEOUT=600
  local value

  while [[ $# -gt 0 ]]; do
    case $1 in
      --)
        shift
        AGENT_EXTRA_ARGS=("$@")
        break
        ;;
      --help|-h)
        show_help
        ;;
      --once)
        ONCE_FLAG=true
        shift
        ;;
      --agent|-a)
        if [ -z "$2" ]; then
          echo "Error: --agent requires a value" >&2
          exit 1
        fi
        RALPH_AGENT=$(normalize_agent_name "$2")
        shift 2
        ;;
      --agent=*)
        RALPH_AGENT=$(normalize_agent_name "${1#*=}")
        shift
        ;;
      --max-iterations|-n)
        if [ -z "$2" ]; then
          echo "Error: --max-iterations requires a value" >&2
          exit 1
        fi
        MAX_ITERATIONS="$2"
        shift 2
        ;;
      --max-iterations=*)
        MAX_ITERATIONS="${1#*=}"
        shift
        ;;
      --max-stalls|--max-stalls=*)
        if [ "$1" = --max-stalls ]; then value="${2:-}"; shift; else value="${1#*=}"; fi
        shift
        value=$(option_value --max-stalls "$value") || exit 1
        if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
          echo "Error: --max-stalls must be a positive number" >&2
          exit 1
        fi
        MAX_STALLS="$value"
        ;;
      --iteration-timeout|--iteration-timeout=*|--max-outage|--max-outage=*|--check-timeout|--check-timeout=*)
        local option="${1%%=*}"
        if [ "$1" = "$option" ]; then value="${2:-}"; shift; else value="${1#*=}"; fi
        shift
        value=$(option_value "$option" "$value") || exit 1
        value=$(parse_duration "$value") || exit 1
        case "$option" in
          --iteration-timeout) ITERATION_TIMEOUT="$value" ;;
          --max-outage) MAX_OUTAGE="$value" ;;
          --check-timeout) CHECK_TIMEOUT="$value" ;;
        esac
        ;;
      [0-9]*)
        MAX_ITERATIONS="$1"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  # --once overrides max-iterations
  if [ "$ONCE_FLAG" = true ]; then
    MAX_ITERATIONS=1
  fi

  if ! is_supported_agent "$RALPH_AGENT"; then
    echo "Error: unsupported agent '$RALPH_AGENT'" >&2
    echo "Supported agents: $(supported_agents_list)" >&2
    exit 1
  fi
}
