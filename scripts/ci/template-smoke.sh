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

log "ok"
