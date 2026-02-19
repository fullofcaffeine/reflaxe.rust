#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

flag="--""example"

if matches="$(git grep -n --fixed-strings -- "$flag" -- README.md AGENTS.md docs scripts templates examples 2>/dev/null)"; then
  echo "[cargo-hx-guard] legacy flag usage found; use project-local flow instead:"
  echo "$matches"
  exit 1
fi

echo "[cargo-hx-guard] ok"
