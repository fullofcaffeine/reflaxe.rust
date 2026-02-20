#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

use_rg=0
if [[ "${REFLAXE_NO_RG:-0}" != "1" ]] && command -v rg >/dev/null 2>&1; then
  use_rg=1
fi

ABSOLUTE_LOCAL_PATTERN="(/Users/[^[:space:]\"'<>()[\\]{}]+|/home/[^[:space:]\"'<>()[\\]{}]+|/var/folders/[^[:space:]\"'<>()[\\]{}]+|/private/var/folders/[^[:space:]\"'<>()[\\]{}]+|[A-Za-z]:\\\\Users\\\\[^[:space:]\"'<>()[\\]{}]+)"

if [[ "$use_rg" -eq 1 ]]; then
  HITS="$(rg -n -P "$ABSOLUTE_LOCAL_PATTERN" \
    --glob '!**/.git/**' \
    --glob '!**/out*/**' \
    --glob '!**/target/**' \
    --glob '!**/node_modules/**' \
    "$ROOT_DIR" || true)"
else
  HITS="$(
    find "$ROOT_DIR" \
      \( -path "$ROOT_DIR/.git/*" -o -path "$ROOT_DIR/out*" -o -path "$ROOT_DIR/target/*" -o -path "$ROOT_DIR/node_modules/*" \) -prune -o \
      -type f -print \
      | while IFS= read -r file_path; do
          grep -nH -E "$ABSOLUTE_LOCAL_PATTERN" "$file_path" || true
        done
  )"
fi

if [[ -z "$HITS" ]]; then
  echo "[guard:local-paths:repo] OK"
  exit 0
fi

echo "[guard:local-paths:repo] ERROR: Absolute local filesystem paths detected in project files."
echo "[guard:local-paths:repo] Use repository-relative paths instead."
echo ""
echo "$HITS"
exit 1
