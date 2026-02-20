#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

PRE_COMMIT_FILE="scripts/hooks/pre-commit"
INSTALLER_FILE="scripts/install-git-hooks.sh"

use_rg=0
if [[ "${REFLAXE_NO_RG:-0}" != "1" ]] && command -v rg >/dev/null 2>&1; then
  use_rg=1
fi

has_pattern() {
  local pattern="$1"
  local file="$2"
  if [[ "$use_rg" -eq 1 ]]; then
    rg -q --fixed-strings -- "$pattern" "$file"
  else
    grep -Fq -- "$pattern" "$file"
  fi
}

ensure_has() {
  local pattern="$1"
  local file="$2"
  local label="$3"
  if ! has_pattern "$pattern" "$file"; then
    echo "[guard:security-wiring] ERROR: missing ${label} (${pattern}) in ${file}" >&2
    exit 1
  fi
}

ensure_has "scripts/lint/local_path_guard_staged.sh" "$PRE_COMMIT_FILE" "staged local-path guard wiring"
ensure_has "run-gitleaks.sh\" --staged" "$PRE_COMMIT_FILE" "shared staged gitleaks wiring"
ensure_has "scripts/hooks/pre-commit" "$INSTALLER_FILE" "hook source wiring"

echo "[guard:security-wiring] OK"
