#!/bin/bash
# Outcome module for ralph.sh
# Sorts a finished run into one outcome the loop acts on
# Dependencies: jq

# Case-insensitive patterns for error events caused by the environment
# (provider, network, credentials, Docker) rather than by the task.
ENV_ERROR_PATTERNS=(
  'exceeded its Copilot budget'
  'rate.?limit|too many requests|\b429\b'
  'overloaded|\b529\b'
  '\b50[0234]\b|internal server error|bad gateway|service unavailable|gateway timeout'
  'ECONNRESET|ECONNREFUSED|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|socket hang up|fetch failed|network'
  '\b401\b|unauthori[sz]ed|invalid api key|authentication'
  'docker daemon not ready|cannot connect to the docker daemon'
)

# Return 0 when the run in history_file failed because of the environment.
# Sets ENV_FAILURE_DETAIL to the matched error message or the wrapper's last line.
# Usage: is_environment_failure <history_file> <exit_status> <recovery_failed>
is_environment_failure() {
  local history_file="$1" exit_status="$2" recovery_failed="$3"
  local pattern started
  pattern=$(IFS='|'; echo "${ENV_ERROR_PATTERNS[*]}")
  ENV_FAILURE_DETAIL=$(jq -Rnr --arg re "$pattern" '
    [inputs | fromjson? | select(type == "object" and .type == "error")]
    | map(select(.error | tostring | test($re; "i")))
    | first | if . == null then empty else
        (.error.data.message // .error.message // (.error | tostring)) end
  ' "$history_file")
  [ -n "$ENV_FAILURE_DETAIL" ] && return 0
  if [ "$exit_status" -ne 0 ] || [ "$recovery_failed" = 1 ]; then
    started=$(jq -Rn '[inputs | fromjson? | select(type == "object" and has("sessionID"))]
      | length' "$history_file")
    if [ "$started" = 0 ]; then
      ENV_FAILURE_DETAIL=$(grep -v -e '^[[:space:]]*$' -e '^Script \(started\|done\) on ' "$history_file" | tail -n 1)
      ENV_FAILURE_DETAIL="${ENV_FAILURE_DETAIL:-wrapper exited with status $exit_status}"
      return 0
    fi
  fi
  return 1
}

# Echo the run's outcome. The first matching outcome wins.
# Usage: classify_run <progress 0|1> <tag_kind BLOCKED|DECIDE|RETRY|""> \
#                     <env_failure 0|1> <timed_out 0|1> <exit_status>
classify_run() {
  local progress="$1" tag_kind="$2" env_failure="$3" timed_out="$4" exit_status="$5"
  if [ "$progress" = 1 ]; then
    echo progress
  elif [ "$tag_kind" = BLOCKED ] || [ "$tag_kind" = DECIDE ]; then
    echo parked
  elif [ "$env_failure" = 1 ] || [ "$tag_kind" = RETRY ]; then
    echo environment
  elif [ "$timed_out" = 1 ]; then
    echo timeout
  elif [ "$exit_status" -ne 0 ]; then
    echo failure
  else
    echo no_progress
  fi
}
