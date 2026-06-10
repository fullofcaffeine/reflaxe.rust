#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

echo "[guard:tracked-artifacts] Checking tracked generated/local artifact paths..."

hits="$(
  git ls-files \
    | awk '
      $0 ~ "(^|/)\\.DS_Store$" { print; next }
      $0 ~ "(^|/)\\.compile_fallback_(optional|group)\\.log$" { print; next }
      $0 ~ "^examples/[^/]+/out(_[^/]+)?/" { print; next }
    '
)"

if [[ -z "$hits" ]]; then
  echo "[guard:tracked-artifacts] OK"
  exit 0
fi

echo "[guard:tracked-artifacts] ERROR: generated/local artifacts are tracked:" >&2
printf '%s\n' "$hits" | sed 's/^/  /' >&2
echo "[guard:tracked-artifacts] Remove these from git; they are ignored scratch outputs, not source." >&2
exit 1
