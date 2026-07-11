#!/usr/bin/env bash
set -euo pipefail

crate_dir="${1:-}"
required_file="${2:-}"

if [[ -z "$crate_dir" || -z "$required_file" ]]; then
  echo "usage: $0 <generated-crate-dir> <required-rust-tests.txt>" >&2
  exit 2
fi

if [[ ! -d "$crate_dir" ]]; then
  echo "[runtime-e2e] error: generated crate directory is missing: ${crate_dir}" >&2
  exit 2
fi

if [[ ! -f "$required_file" ]]; then
  echo "[runtime-e2e] error: required Rust test inventory is missing: ${required_file}" >&2
  exit 2
fi

test_list="$(cd "$crate_dir" && cargo test -q -- --list)"
required_count=0

while IFS= read -r test_name || [[ -n "$test_name" ]]; do
  test_name="${test_name%$'\r'}"
  test_name="${test_name#"${test_name%%[![:space:]]*}"}"
  test_name="${test_name%"${test_name##*[![:space:]]}"}"

  if [[ -z "$test_name" || "$test_name" == \#* ]]; then
    continue
  fi

  required_count=$((required_count + 1))
  if ! grep -Fqx -- "${test_name}: test" <<<"$test_list"; then
    echo "[runtime-e2e] error: required generated Rust test is missing: ${test_name}" >&2
    echo "[runtime-e2e] declared by: ${required_file}" >&2
    echo "[runtime-e2e] generated Cargo tests:" >&2
    printf '%s\n' "$test_list" >&2
    exit 1
  fi
done < "$required_file"

if [[ "$required_count" -eq 0 ]]; then
  echo "[runtime-e2e] error: ${required_file} declares no generated Rust tests" >&2
  exit 1
fi

echo "[runtime-e2e] required generated Rust tests: ${required_count} (${crate_dir})"
