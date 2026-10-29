#!/bin/bash
# Park module for ralph.sh
# Moves a BLOCKED or DECIDE run onto its own branch and resets to the run's base
# Dependencies: tasks.sh

# Commit the working tree, including untracked files, on top of HEAD without
# touching the real index. Echoes the snapshot commit, or HEAD when nothing changed.
snapshot_worktree() {
  local task_id="$1" index_dir tree head
  index_dir=$(mktemp -d) || return 1
  tree=$(GIT_INDEX_FILE="$index_dir/index" git read-tree HEAD &&
    GIT_INDEX_FILE="$index_dir/index" git add -A &&
    GIT_INDEX_FILE="$index_dir/index" git write-tree)
  local status=$?
  rm -rf "$index_dir"
  [ "$status" -eq 0 ] || return 1
  head=$(git rev-parse HEAD) || return 1
  if [ "$tree" = "$(git rev-parse 'HEAD^{tree}')" ]; then
    echo "$head"
  else
    git commit-tree "$tree" -p "$head" -m "wip(ralph): $task_id parked snapshot"
  fi
}

# Echo the first free branch name for a parked task.
free_park_branch() {
  local name="ralph/parked/$1" candidate n=2
  candidate="$name"
  while git show-ref --verify --quiet "refs/heads/$candidate"; do
    candidate="$name-$n"
    n=$((n + 1))
  done
  echo "$candidate"
}

# Save the run on ralph/parked/<task>, reset to base, and record the park.
# Sets PARKED_BRANCH. Returns nonzero before resetting if saving fails.
# Usage: park_run <task_id> <kind> <reason> <base_sha>
park_run() {
  local task_id="$1" kind="$2" reason="$3" base="$4" snapshot
  snapshot=$(snapshot_worktree "$task_id") || return 1
  PARKED_BRANCH=$(free_park_branch "$task_id")
  git branch "$PARKED_BRANCH" "$snapshot" || return 1
  [ "$(git rev-parse "refs/heads/$PARKED_BRANCH")" = "$snapshot" ] || return 1
  git reset -q --hard "$base" || return 1
  git clean -fdq || return 1
  set_task_parked "$task_id" "$kind" "$reason" "$PARKED_BRANCH" "$base" || return 1
  commit_bookkeeping "chore(ralph): park $task_id ($kind)"
}
