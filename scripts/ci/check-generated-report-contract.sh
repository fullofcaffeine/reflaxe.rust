#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture_dir="$root_dir/test/contract/generated_reports"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-rust-report-contract.XXXXXX")"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

haxe_bin="${HAXE_BIN:-}"
if [[ -z "$haxe_bin" ]]; then
  if [[ -x "$root_dir/node_modules/.bin/haxe" ]]; then
    haxe_bin="$root_dir/node_modules/.bin/haxe"
  else
    haxe_bin="haxe"
  fi
fi

compile_reports() {
  local output_dir="$1"
  (
    cd "$fixture_dir"
    "$haxe_bin" compile.hxml -D "rust_output=$output_dir"
  ) >/dev/null
  node "$root_dir/scripts/ci/generated-consumer-contract-check.js" --report-dir "$output_dir" >/dev/null
}

first="$tmp_root/first"
second="$tmp_root/second"
compile_reports "$first"
compile_reports "$second"

for report in metal_report.json contract_report.json runtime_plan.json optimizer_plan.json; do
  if ! cmp -s "$first/$report" "$second/$report"; then
    echo "error: $report is not byte-for-byte repeatable" >&2
    exit 1
  fi
done

echo "[generated-report-contract] OK (schemas + byte-for-byte repeatability)"
