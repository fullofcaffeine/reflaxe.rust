#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="full"

if [ "${1:-}" = "--staged" ]; then
  MODE="staged"
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "[gitleaks] ERROR: gitleaks is required but not installed." >&2
  echo "[gitleaks] Install: https://github.com/gitleaks/gitleaks#installing" >&2
  exit 1
fi

CONFIG_ARGS=()
if [ -f "$ROOT_DIR/.gitleaks.toml" ]; then
  CONFIG_ARGS+=(--config "$ROOT_DIR/.gitleaks.toml")
fi

GITLEAKS_HELP="$(gitleaks --help 2>&1 || true)"

if [ "$MODE" = "staged" ]; then
  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[gitleaks] WARN: --staged requested but no git repo at project root; skipping."
    exit 0
  fi

  echo "[gitleaks] Scanning staged changes"
  if printf '%s' "$GITLEAKS_HELP" | grep -q '\<protect\>'; then
    (cd "$ROOT_DIR" && gitleaks protect --staged --redact "${CONFIG_ARGS[@]}")
  elif printf '%s' "$GITLEAKS_HELP" | grep -q '\<git\>'; then
    (cd "$ROOT_DIR" && gitleaks git --staged --redact "${CONFIG_ARGS[@]}")
  else
    echo "[gitleaks] ERROR: unsupported gitleaks CLI; expected 'protect' or 'git' command." >&2
    exit 1
  fi
  exit 0
fi

echo "[gitleaks] Scanning repository history"
if printf '%s' "$GITLEAKS_HELP" | grep -q '\<detect\>'; then
  gitleaks detect --source "$ROOT_DIR" --redact --log-opts="--all" "${CONFIG_ARGS[@]}"
elif printf '%s' "$GITLEAKS_HELP" | grep -q '\<git\>'; then
  (cd "$ROOT_DIR" && gitleaks git --redact "${CONFIG_ARGS[@]}")
else
  echo "[gitleaks] ERROR: unsupported gitleaks CLI; expected 'detect' or 'git' command." >&2
  exit 1
fi
