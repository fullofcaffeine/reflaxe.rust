#!/usr/bin/env bash

# Runs one command with timing messages while preserving its exact exit status.
#
# Why
# - Timing wrappers commonly print a completion message after the wrapped command.
# - In Bash, that final print becomes the function's status unless the child status is captured and
#   returned explicitly. This is especially dangerous when the wrapper is used under `if ! ...`,
#   where `set -e` does not stop the function after the child fails.
#
# What
# - Prints a caller-selected start and completion prefix around one command.
# - Returns the wrapped command's status unchanged after the completion message is written.
#
# How
# - Executes the command inside an explicit `if`, records either zero or `$?`, then returns that value.
# - `log_fd` is limited to stdout (`1`) or stderr (`2`) so callers retain their existing log stream.
ci_run_timed_command() {
  local label="$1"
  local start_prefix="$2"
  local done_prefix="$3"
  local log_fd="$4"
  shift 4

  local start="$SECONDS"
  if [[ "$log_fd" == "2" ]]; then
    printf '%s%s\n' "$start_prefix" "$label" >&2
  else
    printf '%s%s\n' "$start_prefix" "$label"
  fi

  local status=0
  if "$@"; then
    status=0
  else
    status=$?
  fi

  local elapsed=$((SECONDS - start))
  if [[ "$log_fd" == "2" ]]; then
    printf '%s%s (%ss)\n' "$done_prefix" "$label" "$elapsed" >&2
  else
    printf '%s%s (%ss)\n' "$done_prefix" "$label" "$elapsed"
  fi
  return "$status"
}
