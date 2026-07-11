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

run_timed_step() {
  local label="$1"
  shift
  local start="$SECONDS"
  echo "[harness] ${label}"
  "$@"
  local elapsed=$((SECONDS - start))
  echo "[harness] done: ${label} (${elapsed}s)"
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

snapshot_case_has_compile() {
  local case_dir="$1"
  if [[ -f "$case_dir/compile.hxml" ]]; then
    return 0
  fi

  local candidate
  for candidate in "$case_dir"/compile.*.hxml; do
    [[ -f "$candidate" ]] && return 0
  done

  return 1
}

list_snapshot_cases() {
  local case_dir
  while IFS= read -r case_dir; do
    if snapshot_case_has_compile "$case_dir"; then
      basename "$case_dir"
    fi
  done < <(find test/snapshot -mindepth 1 -maxdepth 1 -type d | sort)
}

run_snapshot_clippy_subset() {
  local configured="${SNAP_CLIPPY_CASES:-v1_smoke portable_profile_smoke metal_v1_smoke}"
  configured="${configured//,/ }"

  local case_name
  for case_name in $configured; do
    if [[ ! -d "test/snapshot/$case_name" ]]; then
      echo "[harness] WARN: snapshot clippy case not found: $case_name"
      continue
    fi
    run_timed_step "snapshot clippy: ${case_name}" bash test/run-snapshots.sh --case "$case_name" --clippy --no-diff
  done
}

run_snapshots() {
  local jobs="${HARNESS_SNAPSHOT_JOBS:-4}"

  if ! [[ "$jobs" =~ ^[0-9]+$ ]]; then
    echo "[harness] WARN: invalid HARNESS_SNAPSHOT_JOBS=$jobs; falling back to serial snapshots"
    jobs=1
  fi

  if [[ "$jobs" -le 1 ]]; then
    bash test/run-snapshots.sh --clippy
    return
  fi

  local log_dir
  log_dir="$(mktemp -d "${TMPDIR:-/tmp}/harness-snapshots.XXXXXX")"

  local cases=()
  local case_name
  while IFS= read -r case_name; do
    cases+=("$case_name")
  done < <(list_snapshot_cases)

  echo "[harness] snapshot parallel jobs: $jobs (${#cases[@]} cases)"

  local fail=0
  local index=0
  local total="${#cases[@]}"

  while [[ "$index" -lt "$total" ]]; do
    local pids=()
    local names=()
    local logs=()
    local slot=0

    while [[ "$slot" -lt "$jobs" && "$index" -lt "$total" ]]; do
      case_name="${cases[$index]}"
      local log_file="$log_dir/${case_name}.log"

      echo "[harness] snapshot queued: ${case_name}"
      (
        bash test/run-snapshots.sh --case "$case_name"
      ) >"$log_file" 2>&1 &

      pids+=("$!")
      names+=("$case_name")
      logs+=("$log_file")

      index=$((index + 1))
      slot=$((slot + 1))
    done

    local i
    for i in "${!pids[@]}"; do
      local status=0
      if wait "${pids[$i]}"; then
        status=0
      else
        status=$?
        fail=1
      fi

      echo "[harness] snapshot log: ${names[$i]}"
      cat "${logs[$i]}"

      if [[ "$status" -ne 0 ]]; then
        echo "[harness] snapshot failed: ${names[$i]} (exit ${status})"
      fi
    done
  done

  rm -rf "$log_dir"

  if [[ "$fail" -ne 0 ]]; then
    return "$fail"
  fi

  # Parallel case runs intentionally skip --clippy so single-case selection does
  # not expand clippy to every snapshot. Preserve the curated clippy contract in
  # one small serial pass.
  run_snapshot_clippy_subset
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

normalize_hxml_for_reuse() {
  local compile_file="$1"
  awk '
    /^[[:space:]]*$/ { next }
    /^-D[[:space:]]+rust_output=/ { next }
    {
      sub(/[[:space:]]+$/, "", $0);
      print $0;
    }
  ' "$compile_file"
}

hxml_equivalent_except_output() {
  local left="$1"
  local right="$2"
  diff -q <(normalize_hxml_for_reuse "$left") <(normalize_hxml_for_reuse "$right") >/dev/null
}

find_reusable_compile() {
  local dir="$1"
  local requested_hxml="$2"
  local requested_file="$dir/$requested_hxml"

  # Validate the requested CI HXML before considering reuse so stale or broken
  # rust_output metadata still fails the harness.
  extract_out_dir "$requested_file" >/dev/null

  local candidate
  while IFS= read -r candidate; do
    local candidate_name
    candidate_name="$(basename "$candidate")"

    if [[ "$candidate_name" == "$requested_hxml" ]]; then
      continue
    fi

    if ! grep -Fxq -- "${dir}/${candidate_name}" "$compiled_hxml_cache_file"; then
      continue
    fi

    if hxml_equivalent_except_output "$requested_file" "$candidate"; then
      printf "%s\n" "$candidate_name"
      return 0
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name 'compile*.hxml' | sort)

  printf "%s\n" "$requested_hxml"
}

compile_example() {
  local dir="$1"
  local hxml="$2"
  local cache_key="${dir}/${hxml}"

  if grep -Fxq -- "$cache_key" "$compiled_hxml_cache_file"; then
    echo "[harness] compile: ${dir} (${hxml}) [cached]"
    return 0
  fi
  run_timed_step "compile: ${dir} (${hxml})" bash -c 'cd "$1" && haxe "$2"' _ "$dir" "$hxml"
  printf "%s\n" "$cache_key" >> "$compiled_hxml_cache_file"
}

run_example() {
  local dir="$1"
  local requested_hxml="$2"
  local hxml
  hxml="$(find_reusable_compile "$dir" "$requested_hxml")"
  local out_dir
  out_dir="$(extract_out_dir "$dir/$hxml")"

  local start="$SECONDS"
  if [[ "$hxml" == "$requested_hxml" ]]; then
    echo "[harness] example: ${dir} (${hxml})"
  else
    echo "[harness] example: ${dir} (${requested_hxml}) [reuse ${hxml}]"
  fi
  compile_example "$dir" "$hxml"
  run_timed_step "cargo test: ${dir}/${out_dir}" bash -c 'cd "$1" && cargo test -q' _ "$dir/$out_dir"
  run_timed_step "cargo run: ${dir}/${out_dir}" bash -c 'cd "$1" && cargo run -q' _ "$dir/$out_dir"
  local elapsed=$((SECONDS - start))
  if [[ "$hxml" == "$requested_hxml" ]]; then
    echo "[harness] done: example: ${dir} (${hxml}) (${elapsed}s)"
  else
    echo "[harness] done: example: ${dir} (${requested_hxml}) [reuse ${hxml}] (${elapsed}s)"
  fi
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

normalize_harness_stage_selector() {
  local raw="${HARNESS_STAGES:-all}"
  raw="${raw//,/ }"
  local stages=()
  local token

  for token in $raw; do
    case "$token" in
      all|snapshots|conformance|policy|packaging|examples|parity)
        stages+=("$token")
        ;;
      *)
        echo "[harness] error: unknown HARNESS_STAGES entry: $token" >&2
        echo "[harness] valid entries: all, snapshots, conformance, policy, packaging, examples, parity" >&2
        exit 2
        ;;
    esac
  done

  if [[ "${#stages[@]}" -eq 0 ]]; then
    echo "[harness] error: HARNESS_STAGES did not contain any stages" >&2
    exit 2
  fi

  HARNESS_STAGE_SET=" ${stages[*]} "
  if [[ "$HARNESS_STAGE_SET" == *" all "* ]]; then
    HARNESS_STAGE_SET=" all "
  fi
  echo "[harness] selected stages:${HARNESS_STAGE_SET}"
}

harness_stage_selected() {
  local stage="$1"
  [[ "$HARNESS_STAGE_SET" == *" all "* || "$HARNESS_STAGE_SET" == *" $stage "* ]]
}

run_snapshots_group() {
  run_stage "snapshots" run_snapshots
  intermediate_cleanup "snapshots"
}

run_conformance_group() {
  run_stage "semantic diff (portable)" python3 test/run-semantic-diff.py
  intermediate_cleanup "semantic-diff"

  run_stage "semantic diff (lanes)" python3 test/run-semantic-diff.py --suite lanes
  intermediate_cleanup "semantic-diff-lanes"

  run_stage "upstream stdlib sweep" bash test/run-upstream-stdlib-sweep.sh
  intermediate_cleanup "upstream-stdlib-sweep"

  run_stage "family std sync verify" python3 tools/family_std_sync.py --mode verify
  intermediate_cleanup "family-stdlib-sync"

  run_stage "tier1 api surface smoke" python3 test/run-tier1-api-surface-smoke.py
  intermediate_cleanup "tier1-api-surface-smoke"
}

run_policy_group() {
  run_stage "generated report schema and repeatability contract" bash scripts/ci/check-generated-report-contract.sh
  intermediate_cleanup "generated-report-contract"

  run_stage "stable diagnostic identifier contract" bash scripts/ci/check-diagnostic-contract.sh
  intermediate_cleanup "diagnostic-contract"

  run_stage "metal boundary policy" bash scripts/ci/check-metal-policy.sh
  intermediate_cleanup "metal-policy"

  run_stage "define docs guard" bash scripts/lint/defines_doc_guard.sh
  intermediate_cleanup "defines-doc-guard"

  run_stage "portable native-import diagnostics" bash scripts/ci/check-portable-native-import-diagnostics.sh
  intermediate_cleanup "portable-native-import-diagnostics"

  run_stage "metal fallback count guard" bash scripts/ci/check-metal-fallback-counts.sh
  intermediate_cleanup "metal-fallback-count-guard"

  run_stage "metal idiom count guard" bash scripts/ci/check-metal-idiom-counts.sh
  intermediate_cleanup "metal-idiom-count-guard"
}

run_packaging_group() {
  if is_truthy "${HARNESS_SKIP_PACKAGE_SMOKE:-0}"; then
    echo "[harness] package smoke skipped (HARNESS_SKIP_PACKAGE_SMOKE=1)"
  else
    run_stage "package smoke" env PACKAGE_ZIP_REL=".cache/package-smoke/reflaxe.rust-audit.zip" bash scripts/ci/package-smoke.sh
    intermediate_cleanup "package-smoke"
  fi

  run_stage "generated artifact ownership contract" env GENERATED_ARTIFACT_SKIP_CARGO_FAILURE=1 bash scripts/ci/check-generated-artifact-contract.sh
  intermediate_cleanup "generated-artifact-contract"

  run_stage "cargo failure propagation" bash scripts/ci/check-cargo-failure-propagation.sh
  intermediate_cleanup "cargo-failure-propagation"

  run_stage "template smoke" bash scripts/ci/template-smoke.sh
  intermediate_cleanup "template-smoke"
}

run_examples_group() {
  # Example compiles trigger cargo builds via the Rust backend. Share one target
  # dir so all example crates reuse artifacts (keeps local/CI runtime reasonable).
  if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
    export CARGO_TARGET_DIR="${EXAMPLES_CARGO_TARGET_DIR:-$root_dir/.cache/examples-target}"
  fi

  run_stage "examples (compile-only developer variants)" run_examples_compile_only

  run_stage "examples (CI run matrix)" run_examples_ci_matrix
}

run_parity_group() {
  run_stage "profile_storyboard native parity" bash examples/profile_storyboard/scripts/compare-native.sh
}

normalize_harness_stage_selector

if harness_stage_selected "snapshots"; then
  run_snapshots_group
fi

if harness_stage_selected "conformance"; then
  run_conformance_group
fi

if harness_stage_selected "policy"; then
  run_policy_group
fi

if harness_stage_selected "packaging"; then
  run_packaging_group
fi

if harness_stage_selected "examples"; then
  run_examples_group
fi

if harness_stage_selected "parity"; then
  run_parity_group
fi

echo "[harness] ok"
