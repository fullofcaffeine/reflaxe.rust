#!/usr/bin/env bash
set -euo pipefail

# Guard: prevent demo/app-specific identifiers from leaking into compiler sources.
# Rationale: compiler code should remain generic and not accumulate example-driven naming.

TARGET_DIR='src/reflaxe/rust'

# NOTE: This list is intentionally small. Add entries only when we observe real contamination.
# `ratatui` is a general-purpose crate and may appear in docs/examples for Cargo metadata.
PATTERN='(tui_todo|thread_pool_smoke)'
use_rg=0
if [[ "${REFLAXE_NO_RG:-0}" != "1" ]] && command -v rg >/dev/null 2>&1; then
  use_rg=1
fi

echo "[guard:names] Scanning ${TARGET_DIR} for app-specific identifiers..."

if [[ "$use_rg" -eq 1 ]]; then
  if rg -n -e "${PATTERN}" "${TARGET_DIR}" --no-heading --hidden --glob '!**/docs/**' --glob '!**/test/**' ; then
    echo "[guard:names] ERROR: App-specific identifiers found in compiler sources." >&2
    exit 1
  fi
else
  if grep -RInE "${PATTERN}" "${TARGET_DIR}" --exclude-dir=docs --exclude-dir=test ; then
    echo "[guard:names] ERROR: App-specific identifiers found in compiler sources." >&2
    exit 1
  fi
fi

echo "[guard:names] OK"
