#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
repro_root="${root_dir}/test/repro/upstream_open_gaps"

HAXE_BIN="${HAXE_BIN:-haxe}"
CARGO_BIN="${CARGO_BIN:-cargo}"

run_expected_cargo_failure() {
  local case_name="$1"
  local bead="$2"
  local expected_regex="$3"
  local case_dir="${repro_root}/${case_name}"
  local log_file="${case_dir}/out/cargo-build.log"

  rm -rf "${case_dir}/out"

  (
    cd "$case_dir"
    "$HAXE_BIN" compile.hxml
  )

  set +e
  (
    cd "${case_dir}/out"
    "$CARGO_BIN" build --quiet
  ) >"$log_file" 2>&1
  local code=$?
  set -e

  if [[ "$code" -eq 0 ]]; then
    echo "[upstream-open-gap-repros] ${case_name}: Cargo build unexpectedly passed; update this repro into a passing fixture and close ${bead}." >&2
    exit 1
  fi

  if ! grep -Eq "$expected_regex" "$log_file"; then
    echo "[upstream-open-gap-repros] ${case_name}: expected failure signature for ${bead} was not found." >&2
    echo "[upstream-open-gap-repros] expected regex: ${expected_regex}" >&2
    sed -n '1,160p' "$log_file" >&2
    exit 1
  fi

  echo "[upstream-open-gap-repros] ${case_name}: expected ${bead} failure observed"
}

run_expected_cargo_failure "path_directory" "haxe.rust-lj8" "haxe_io_path|Path::directory|could not find"
run_expected_cargo_failure "string_last_index_of" "haxe.rust-7s4" "lastIndexOf|no method named"

echo "[upstream-open-gap-repros] all expected failures observed"
