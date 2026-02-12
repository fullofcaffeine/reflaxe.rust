#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

current_step="bootstrap"

log() {
  printf '[windows-smoke] %s\n' "$*"
}

run_step() {
  local label="$1"
  shift

  local step_started
  step_started="$(date +%s)"
  current_step="$label"
  log "start: $label"
  "$@"
  local elapsed
  elapsed="$(( $(date +%s) - step_started ))"
  log "done:  $label (${elapsed}s)"
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

cleanup_artifacts() {
  local original_exit="${1:-0}"
  local cleanup_args=()

  if is_truthy "${KEEP_ARTIFACTS:-0}"; then
    log "keep artifacts enabled (KEEP_ARTIFACTS=1)"
    return "$original_exit"
  fi

  if is_truthy "${WINDOWS_SMOKE_CLEAN_OUTPUTS:-1}"; then
    cleanup_args+=(--outputs)
  fi

  if is_truthy "${WINDOWS_SMOKE_CLEAN_CACHE:-1}"; then
    cleanup_args+=(--cache)
  fi

  if [[ "${#cleanup_args[@]}" -gt 0 ]]; then
    log "cleanup (${cleanup_args[*]})"
    if ! "$root_dir/scripts/ci/clean-artifacts.sh" "${cleanup_args[@]}"; then
      log "WARN: artifact cleanup failed"
    fi
  fi

  return "$original_exit"
}

trap 'cleanup_artifacts $?' EXIT

extract_out_dir() {
  local compile_file="$1"
  local out_dir
  out_dir="$(awk '
    /^-D[[:space:]]+rust_output=/ {
      sub(/^-D[[:space:]]+rust_output=/, "", $0);
      print $0;
      exit;
    }
  ' "$compile_file")"
  if [[ -z "${out_dir:-}" ]]; then
    echo "error: missing '-D rust_output=...' in $compile_file" >&2
    exit 2
  fi
  printf "%s\n" "$out_dir"
}

run_example() {
  local dir="$1"
  local hxml=""

  if [[ -f "$dir/compile.ci.hxml" ]]; then
    hxml="compile.ci.hxml"
  elif [[ -f "$dir/compile.hxml" ]]; then
    hxml="compile.hxml"
  else
    echo "error: no compile.hxml/compile.ci.hxml in $dir" >&2
    exit 2
  fi

  local out_dir
  out_dir="$(extract_out_dir "$dir/$hxml")"

  log "compile: ${dir} (${hxml})"
  (cd "$dir" && haxe "$hxml")
  (cd "$dir/$out_dir" && cargo test -q)
  (cd "$dir/$out_dir" && cargo run -q)
}

log "snapshots"
run_step "snapshot hello_trace" bash test/run-snapshots.sh --case hello_trace
run_step "snapshot sys_io" bash test/run-snapshots.sh --case sys_io

if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  export CARGO_TARGET_DIR="$root_dir/.cache/examples-target-windows-smoke"
fi

log "examples"
run_step "example sys_file_io" run_example "examples/sys_file_io"
run_step "example sys_net_loopback" run_example "examples/sys_net_loopback"

log "ok"
