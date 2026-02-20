#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

log() {
  printf '[template-smoke] %s\n' "$*"
}

is_truthy() {
  local value="${1:-}"
  case "$value" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

tmp_root="$root_dir/.cache/template-smoke"
app_dir="$tmp_root/hx_template_smoke"

cleanup() {
  local original_exit="${1:-0}"
  if is_truthy "${KEEP_ARTIFACTS:-0}"; then
    log "keep artifacts enabled (KEEP_ARTIFACTS=1)"
    return "$original_exit"
  fi
  rm -rf "$tmp_root"
  return "$original_exit"
}

trap 'cleanup $?' EXIT

mkdir -p "$tmp_root"

log "scaffold template project"
bash scripts/dev/new-project.sh "$app_dir" --force >/dev/null

log "verify generated security plumbing files"
(
  cd "$app_dir"
  required_files=(
    ".gitleaks.toml"
    "scripts/security/run-gitleaks.sh"
    "scripts/lint/local_path_guard_staged.sh"
    "scripts/lint/local_path_guard_repo.sh"
    "scripts/lint/security_wiring_guard.sh"
    "scripts/hooks/pre-commit"
    "scripts/install-git-hooks.sh"
    "scripts/dev/check-guards.sh"
  )
  for path in "${required_files[@]}"; do
    if [[ ! -f "$path" ]]; then
      echo "[template-smoke] missing required template file: $path" >&2
      exit 1
    fi
  done
)

log "run generated project guard checks"
(
  cd "$app_dir"
  bash scripts/dev/check-guards.sh
)

log "install generated pre-commit hook"
(
  cd "$app_dir"
  git init -q
  bash scripts/install-git-hooks.sh
  test -x .git/hooks/pre-commit
)

if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  export CARGO_TARGET_DIR="$root_dir/.cache/template-smoke-target"
fi

log "run task hxml matrix"
(
  cd "$app_dir"
  haxe compile.build.hxml
  haxe compile.hxml
  haxe compile.run.hxml
  haxe compile.release.hxml
  haxe compile.release.run.hxml
)

log "run cargo hx task driver"
(
  cd "$app_dir"
  cargo hx --action run
  cargo hx --action test
  cargo hx --action build --release
)

log "run root cargo-hx wrapper with --project"
(
  cd "$root_dir"
  # Keep the wrapper tool target dir isolated so env!("CARGO_MANIFEST_DIR")
  # points at the repo script path, not the generated template copy.
  CARGO_TARGET_DIR="$root_dir/.cache/template-smoke-root-hx-target" \
    cargo run --quiet --manifest-path tools/hx/Cargo.toml -- --project "$app_dir" --action test
)

log "watcher one-shot smoke"
(
  cd "$app_dir"
  bash scripts/dev/watch-haxe-rust.sh --hxml compile.hxml --once --mode test --no-haxe-server
)

log "ok"
