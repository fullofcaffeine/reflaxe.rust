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
    echo "[harness] keep artifacts enabled (KEEP_ARTIFACTS=1)"
    return "$original_exit"
  fi

  if is_truthy "${HARNESS_CLEAN_OUTPUTS:-1}"; then
    cleanup_args+=(--outputs)
  fi

  if is_truthy "${HARNESS_CLEAN_CACHE:-1}"; then
    cleanup_args+=(--cache)
  fi

  if [[ "${#cleanup_args[@]}" -gt 0 ]]; then
    echo "[harness] cleanup (${cleanup_args[*]})"
    if ! "$root_dir/scripts/ci/clean-artifacts.sh" "${cleanup_args[@]}"; then
      echo "[harness] WARN: artifact cleanup failed"
    fi
  fi

  return "$original_exit"
}

trap 'cleanup_artifacts $?' EXIT

intermediate_cleanup() {
  local stage="${1:-unknown}"
  local cleanup_args=()

  if is_truthy "${KEEP_ARTIFACTS:-0}"; then
    echo "[harness] keep artifacts enabled (skip intermediate cleanup after ${stage})"
    return 0
  fi

  if is_truthy "${HARNESS_CLEAN_OUTPUTS:-1}"; then
    cleanup_args+=(--outputs)
  fi

  if is_truthy "${HARNESS_CLEAN_CACHE:-1}"; then
    cleanup_args+=(--cache)
  fi

  if [[ "${#cleanup_args[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "[harness] intermediate cleanup after ${stage} (${cleanup_args[*]})"
  if ! "$root_dir/scripts/ci/clean-artifacts.sh" "${cleanup_args[@]}"; then
    echo "[harness] WARN: intermediate cleanup failed after ${stage}"
  fi
}

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

compile_example() {
  local dir="$1"
  local hxml="$2"

  echo "[harness] compile: ${dir} (${hxml})"
  (cd "$dir" && haxe "$hxml")
}

run_example() {
  local dir="$1"
  local hxml="$2"
  local out_dir
  out_dir="$(extract_out_dir "$dir/$hxml")"

  compile_example "$dir" "$hxml"
  (cd "$dir/$out_dir" && cargo test -q)
  (cd "$dir/$out_dir" && cargo run -q)
}

echo "[harness] snapshots"
bash test/run-snapshots.sh --clippy
intermediate_cleanup "snapshots"

echo "[harness] upstream stdlib sweep"
bash test/run-upstream-stdlib-sweep.sh
intermediate_cleanup "upstream-stdlib-sweep"

# Example compiles trigger cargo builds via the Rust backend. Share one target dir
# so all example crates reuse artifacts (keeps local/CI runtime reasonable).
if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  export CARGO_TARGET_DIR="${EXAMPLES_CARGO_TARGET_DIR:-$root_dir/.cache/examples-target}"
fi

echo "[harness] examples (compile-only developer variants)"
while IFS= read -r compile_file; do
  example_dir="$(dirname "$compile_file")"
  compile_name="$(basename "$compile_file")"
  compile_example "$example_dir" "$compile_name"
done < <(find examples -mindepth 2 -maxdepth 2 -type f \( -name 'compile.hxml' -o -name 'compile.rusty.hxml' \) | sort)

echo "[harness] examples (CI run matrix)"
while IFS= read -r example_dir; do
  if [[ -f "$example_dir/compile.ci.hxml" ]]; then
    run_example "$example_dir" "compile.ci.hxml"
  elif [[ -f "$example_dir/compile.hxml" ]]; then
    run_example "$example_dir" "compile.hxml"
  fi

  if [[ -f "$example_dir/compile.rusty.ci.hxml" ]]; then
    run_example "$example_dir" "compile.rusty.ci.hxml"
  fi
done < <(find examples -mindepth 1 -maxdepth 1 -type d | sort)

echo "[harness] ok"
