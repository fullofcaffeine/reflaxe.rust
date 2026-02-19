#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

use_rg=0
if [[ "${REFLAXE_NO_RG:-0}" != "1" ]] && command -v rg >/dev/null 2>&1; then
  use_rg=1
fi

BASE_COMMIT=""
if git rev-parse --verify origin/main >/dev/null 2>&1; then
  BASE_COMMIT="$(git merge-base HEAD origin/main)"
elif git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  BASE_COMMIT="$(git rev-parse HEAD^)"
fi

if [ -z "$BASE_COMMIT" ]; then
  echo "[guard:local-paths:repo] WARN: no diff base found; skipping."
  exit 0
fi

ADDED_LINES="$(
  git diff --unified=0 --no-color "$BASE_COMMIT"...HEAD -- . \
    | awk '
      /^diff --git / { file = ""; next }
      /^\+\+\+ / {
        file = $2
        if (file == "/dev/null") {
          file = ""
        } else {
          sub(/^[a-z]\//, "", file)
        }
        next
      }
      /^\+/ && $0 !~ /^\+\+\+/ && file != "" {
        print file ":" substr($0, 2)
      }
    '
)"

if [[ -z "$ADDED_LINES" ]]; then
  echo "[guard:local-paths:repo] OK"
  exit 0
fi

ABSOLUTE_LOCAL_PATTERN="(/Users/[^[:space:]\"'<>()[\\]{}]+|/home/[^[:space:]\"'<>()[\\]{}]+|/var/folders/[^[:space:]\"'<>()[\\]{}]+|/private/var/folders/[^[:space:]\"'<>()[\\]{}]+|[A-Za-z]:\\\\Users\\\\[^[:space:]\"'<>()[\\]{}]+)"
if [[ "$use_rg" -eq 1 ]]; then
  HITS="$(printf '%s\n' "$ADDED_LINES" | rg -n -P "$ABSOLUTE_LOCAL_PATTERN" || true)"
else
  HITS="$(printf '%s\n' "$ADDED_LINES" | grep -En "$ABSOLUTE_LOCAL_PATTERN" || true)"
fi

if [[ -z "$HITS" ]]; then
  echo "[guard:local-paths:repo] OK"
  exit 0
fi

echo "[guard:local-paths:repo] ERROR: Absolute local filesystem paths detected in tracked files."
echo "[guard:local-paths:repo] Use repository-relative paths instead."
echo ""
echo "$HITS"
exit 1
