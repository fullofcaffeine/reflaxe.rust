#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
example_dir="$root_dir/examples/profile_storyboard"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/profile-storyboard-compare.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

generated_out="$tmp_dir/generated.txt"
native_out="$tmp_dir/native.txt"

echo "[compare-native] build+run generated metal example"
(cd "$example_dir" && cargo hx --profile metal --action build >/dev/null)
(cd "$example_dir/out_metal" && cargo run -q > "$generated_out")

echo "[compare-native] build+run native baseline"
(cd "$example_dir/native" && cargo run -q > "$native_out")

if ! diff -u "$native_out" "$generated_out" >/dev/null; then
  echo "[compare-native] ERROR: output mismatch between generated metal and native baseline" >&2
  diff -u "$native_out" "$generated_out" >&2 || true
  exit 1
fi

echo "[compare-native] OK: generated metal output matches native baseline"
