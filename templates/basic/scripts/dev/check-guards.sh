#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "[guards] local path scan"
bash "$ROOT_DIR/scripts/lint/local_path_guard_repo.sh"

echo "[guards] security wiring check"
bash "$ROOT_DIR/scripts/lint/security_wiring_guard.sh"

if command -v gitleaks >/dev/null 2>&1; then
  echo "[guards] gitleaks (full history)"
  bash "$ROOT_DIR/scripts/security/run-gitleaks.sh"
else
  echo "[guards] WARN: gitleaks not found; skipping secret scan"
fi

echo "[guards] OK"
