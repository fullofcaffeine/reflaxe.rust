#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

# CI runners do not always include the internal tracker CLI.
# Skip this guard when unavailable instead of failing unrelated jobs.
if ! command -v bd >/dev/null 2>&1; then
  echo "[docs] internal tracker CLI not found; skipping progress-tracker sync check"
  exit 0
fi

before_progress="$(mktemp)"
before_vision="$(mktemp)"
trap 'rm -f "$before_progress" "$before_vision"' EXIT

cp docs/progress-tracker.md "$before_progress"
cp docs/vision-vs-implementation.md "$before_vision"

node scripts/docs/sync-progress-tracker.js

progress_changed=0
vision_changed=0
if ! cmp -s "$before_progress" docs/progress-tracker.md; then
  progress_changed=1
fi
if ! cmp -s "$before_vision" docs/vision-vs-implementation.md; then
  vision_changed=1
fi

if [[ "$progress_changed" -eq 1 || "$vision_changed" -eq 1 ]]; then
  echo "[docs] progress tracker docs are stale. Run: npm run docs:sync:progress"
  if [[ "$progress_changed" -eq 1 ]]; then
    git --no-pager diff --no-index -- "$before_progress" docs/progress-tracker.md || true
  fi
  if [[ "$vision_changed" -eq 1 ]]; then
    git --no-pager diff --no-index -- "$before_vision" docs/vision-vs-implementation.md || true
  fi
  exit 1
fi

echo "[docs] tracker blocks are in sync"
