#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

stage_timings_file="$(mktemp "${TMPDIR:-/tmp}/harness-stage-timings.XXXXXX")"
compiled_hxml_cache_file="$(mktemp "${TMPDIR:-/tmp}/harness-compiled-hxml.XXXXXX")"

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

  rm -f "$stage_timings_file" "$compiled_hxml_cache_file" || true

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

record_stage_timing() {
  local stage="${1:-unknown}"
  local elapsed="${2:-0}"
  printf "%s\t%s\n" "$stage" "$elapsed" >> "$stage_timings_file"
}

print_stage_timings() {
  if [[ ! -s "$stage_timings_file" ]]; then
    return 0
  fi
  echo "[harness] stage timings (seconds)"
  local total=0
  while IFS=$'\t' read -r stage elapsed; do
    printf "[harness]   %s: %ss\n" "$stage" "$elapsed"
    total=$((total + elapsed))
  done < "$stage_timings_file"
  printf "[harness]   total: %ss\n" "$total"
}

run_stage() {
  local stage="${1:-unknown}"
  shift || true
  local start="$SECONDS"
  echo "[harness] ${stage}"
  "$@"
  local elapsed=$((SECONDS - start))
  record_stage_timing "$stage" "$elapsed"
}

trap 'status=$?; print_stage_timings; cleanup_artifacts "$status"' EXIT

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
  local cache_key="${dir}/${hxml}"

  if grep -Fxq -- "$cache_key" "$compiled_hxml_cache_file"; then
    echo "[harness] compile: ${dir} (${hxml}) [cached]"
    return 0
  fi
  echo "[harness] compile: ${dir} (${hxml})"
  (cd "$dir" && haxe "$hxml")
  printf "%s\n" "$cache_key" >> "$compiled_hxml_cache_file"
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

run_examples_compile_only() {
  while IFS= read -r compile_file; do
    example_dir="$(dirname "$compile_file")"
    compile_name="$(basename "$compile_file")"
    compile_example "$example_dir" "$compile_name"
  done < <(find examples -mindepth 2 -maxdepth 2 -type f -name 'compile*.hxml' ! -name '*.ci.hxml' | sort)
}

run_examples_ci_matrix() {
  while IFS= read -r example_dir; do
    ci_found=0
    while IFS= read -r ci_compile; do
      ci_found=1
      run_example "$example_dir" "$(basename "$ci_compile")"
    done < <(find "$example_dir" -mindepth 1 -maxdepth 1 -type f -name 'compile*.ci.hxml' | sort)

    if [[ "$ci_found" -eq 0 && -f "$example_dir/compile.hxml" ]]; then
      run_example "$example_dir" "compile.hxml"
    fi
  done < <(find examples -mindepth 1 -maxdepth 1 -type d | sort)
}

run_stage "snapshots" bash test/run-snapshots.sh --clippy
intermediate_cleanup "snapshots"

run_stage "semantic diff (portable)" python3 test/run-semantic-diff.py
intermediate_cleanup "semantic-diff"

run_stage "semantic diff (lanes)" python3 test/run-semantic-diff.py --suite lanes
intermediate_cleanup "semantic-diff-lanes"

run_stage "metal boundary policy" bash scripts/ci/check-metal-policy.sh
intermediate_cleanup "metal-policy"

run_stage "define docs guard" bash scripts/lint/defines_doc_guard.sh
intermediate_cleanup "defines-doc-guard"

run_stage "metal fallback count guard" bash scripts/ci/check-metal-fallback-counts.sh
intermediate_cleanup "metal-fallback-count-guard"

run_stage "upstream stdlib sweep" bash test/run-upstream-stdlib-sweep.sh
intermediate_cleanup "upstream-stdlib-sweep"

run_stage "family std sync verify" python3 tools/family_std_sync.py --mode verify
intermediate_cleanup "family-stdlib-sync"

run_stage "tier1 api surface smoke" python3 test/run-tier1-api-surface-smoke.py
intermediate_cleanup "tier1-api-surface-smoke"

run_stage "package smoke" env PACKAGE_ZIP_REL=".cache/package-smoke/reflaxe.rust-audit.zip" bash scripts/ci/package-smoke.sh
intermediate_cleanup "package-smoke"

run_stage "template smoke" bash scripts/ci/template-smoke.sh
intermediate_cleanup "template-smoke"

# Example compiles trigger cargo builds via the Rust backend. Share one target dir
# so all example crates reuse artifacts (keeps local/CI runtime reasonable).
if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  export CARGO_TARGET_DIR="${EXAMPLES_CARGO_TARGET_DIR:-$root_dir/.cache/examples-target}"
fi

run_stage "examples (compile-only developer variants)" run_examples_compile_only

run_stage "examples (CI run matrix)" run_examples_ci_matrix

run_stage "profile_storyboard native parity" bash examples/profile_storyboard/scripts/compare-native.sh

echo "[harness] ok"
