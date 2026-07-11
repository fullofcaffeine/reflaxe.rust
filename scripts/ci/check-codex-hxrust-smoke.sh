#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="${CODEX_HXRUST_DIR:-"${ROOT_DIR}/../codex-hxrust"}"
APP_LABEL="${CODEX_HXRUST_LABEL:-../codex-hxrust}"
MODE="${CODEX_HXRUST_QA_MODE:-generated-cargo}"

# Runs codex-hxrust's normal generated-Cargo command as an independent consumer compatibility check.
#
# Default mode delegates to codex-hxrust's generated Cargo gate:
# - regenerate portable Rust from Haxe,
# - verify generated Cargo.toml/Cargo.lock,
# - run cargo check --locked,
# - run cargo test --locked,
# - repeat the same sequence for metal.
#
# `cargo test` only exercises runtime behavior that codex-hxrust independently owns as application
# behavior. Compiler-specific runtime and generated-output contracts stay in haxe.rust.
describe_git() {
  local dir="$1"
  local rev="unknown"
  local dirty=""

  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    rev="$(git -C "$dir" rev-parse --short HEAD)"
    if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
      dirty="-dirty"
    fi
  fi

  printf '%s%s' "$rev" "$dirty"
}

if [[ "$MODE" != "generated-cargo" && "$MODE" != "metal" && "$MODE" != "portable" ]]; then
  echo "[codex-hxrust] error: CODEX_HXRUST_QA_MODE must be generated-cargo, metal, or portable." >&2
  exit 2
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "[codex-hxrust] skip: sibling app checkout not found at ${APP_LABEL}."
  exit 0
fi

if [[ ! -f "${APP_DIR}/package.json" ]]; then
  echo "[codex-hxrust] error: ${APP_LABEL}/package.json is missing." >&2
  exit 2
fi

compiler_version="$(node -p "require(process.argv[1]).version" "${ROOT_DIR}/package.json" 2>/dev/null || echo "unknown")"
compiler_rev="$(describe_git "$ROOT_DIR")"
app_rev="$(describe_git "$APP_DIR")"

echo "[codex-hxrust] compiler: reflaxe.rust ${compiler_version} (${compiler_rev})"
echo "[codex-hxrust] app: ${app_rev} (${APP_LABEL})"
echo "[codex-hxrust] mode: ${MODE}"

case "$MODE" in
  generated-cargo)
    (cd "$APP_DIR" && npm run test:generated-cargo)
    ;;
  metal)
    (cd "$APP_DIR" && npm run hx:metal)
    ;;
  portable)
    (cd "$APP_DIR" && npm run hx:portable)
    ;;
esac
