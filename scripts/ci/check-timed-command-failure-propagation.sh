#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$root_dir/scripts/ci/timed-command.sh"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-rust-timed-command.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

# The conditional call is intentional: it reproduces the shell context in which the old snapshot
# wrapper continued after a failed `diff` and returned the trailing log command's success status.
failure_log="$tmp_root/failure.log"
failure_status=0
if ci_run_timed_command "expected failure" "start: " "done: " 1 bash -c 'exit 23' >"$failure_log" 2>&1; then
  failure_status=0
else
  failure_status=$?
fi
if [[ "$failure_status" -ne 23 ]]; then
  echo "error: timed command returned $failure_status instead of child status 23" >&2
  sed -n '1,80p' "$failure_log" >&2
  exit 1
fi

success_log="$tmp_root/success.log"
ci_run_timed_command "expected success" "start: " "done: " 1 bash -c 'exit 0' >"$success_log" 2>&1

if ! grep -q '^start: expected failure$' "$failure_log" || ! grep -q '^done: expected failure (' "$failure_log"; then
  echo "error: timed failure logging contract drifted" >&2
  sed -n '1,80p' "$failure_log" >&2
  exit 1
fi
if ! grep -q '^start: expected success$' "$success_log" || ! grep -q '^done: expected success (' "$success_log"; then
  echo "error: timed success logging contract drifted" >&2
  sed -n '1,80p' "$success_log" >&2
  exit 1
fi

echo "[timed-command-failure-propagation] ok"
