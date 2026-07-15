#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$ROOT_DIR/.git/hooks"
SRC_PRE_COMMIT="$ROOT_DIR/scripts/hooks/pre-commit"
DEST_PRE_COMMIT="$HOOKS_DIR/pre-commit"
DEST_CHAINED_PRE_COMMIT="$HOOKS_DIR/pre-commit.old"
REPO_HOOK_END_MARKER="# --- END REFLAXE.RUST REPOSITORY PRE-COMMIT ---"

is_repo_pre_commit() {
  local hook_path="$1"

  if [ ! -f "$hook_path" ]; then
    return 1
  fi

  if grep -Fq "$REPO_HOOK_END_MARKER" "$hook_path"; then
    return 0
  fi

  # Recognize repository hooks installed before the explicit boundary marker
  # existed. Requiring all long-lived validation signatures avoids deleting an
  # unrelated user-managed chained hook during the one-time migration.
  grep -Fq '[pre-commit] Running local path guard on staged changes...' "$hook_path" \
    && grep -Fq 'scripts/lint/local_path_guard_staged.sh' "$hook_path" \
    && grep -Fq 'scripts/security/run-gitleaks.sh' "$hook_path" \
    && grep -Fq '[pre-commit] OK' "$hook_path"
}

if [ ! -d "$ROOT_DIR/.git" ]; then
  echo "[hooks:install] ERROR: .git directory not found at $ROOT_DIR" >&2
  echo "[hooks:install] Initialize git first: git init" >&2
  exit 1
fi

mkdir -p "$HOOKS_DIR"

if is_repo_pre_commit "$DEST_CHAINED_PRE_COMMIT"; then
  rm "$DEST_CHAINED_PRE_COMMIT"
  echo "[hooks:install] Removed legacy repository pre-commit chain."
fi

cp "$SRC_PRE_COMMIT" "$DEST_PRE_COMMIT"
chmod +x "$DEST_PRE_COMMIT"

if command -v bd >/dev/null 2>&1 && [ -d "$ROOT_DIR/.beads" ]; then
  (
    cd "$ROOT_DIR"
    bd hooks install --chain
  )
  echo "[hooks:install] Installed repository pre-commit hook with Beads integration -> $DEST_PRE_COMMIT"
else
  echo "[hooks:install] Installed pre-commit hook -> $DEST_PRE_COMMIT"
fi
