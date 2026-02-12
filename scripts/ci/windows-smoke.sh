#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

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
    echo "[windows-smoke] keep artifacts enabled (KEEP_ARTIFACTS=1)"
    return "$original_exit"
  fi

  if is_truthy "${WINDOWS_SMOKE_CLEAN_OUTPUTS:-1}"; then
    cleanup_args+=(--outputs)
  fi

  if is_truthy "${WINDOWS_SMOKE_CLEAN_CACHE:-1}"; then
    cleanup_args+=(--cache)
  fi

  if [[ "${#cleanup_args[@]}" -gt 0 ]]; then
    echo "[windows-smoke] cleanup (${cleanup_args[*]})"
    if ! "$root_dir/scripts/ci/clean-artifacts.sh" "${cleanup_args[@]}"; then
      echo "[windows-smoke] WARN: artifact cleanup failed"
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

  echo "[windows-smoke] compile: ${dir} (${hxml})"
  (cd "$dir" && haxe "$hxml")
  (cd "$dir/$out_dir" && cargo test -q)
  (cd "$dir/$out_dir" && cargo run -q)
}

echo "[windows-smoke] snapshots"
bash test/run-snapshots.sh --case hello_trace
bash test/run-snapshots.sh --case sys_io

if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  export CARGO_TARGET_DIR="$root_dir/.cache/examples-target-windows-smoke"
fi

echo "[windows-smoke] examples"
run_example "examples/sys_file_io"
run_example "examples/sys_net_loopback"

echo "[windows-smoke] ok"
