#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

cache_dir="$root_dir/.cache/portable-native-import-diagnostics"
rm -rf "$cache_dir"
mkdir -p "$cache_dir"

haxe_bin="${HAXE_BIN:-haxe}"

run_compile() {
  local label="$1"
  shift
  local log_file="$cache_dir/${label}.log"
  if "$haxe_bin" "$@" >"$log_file" 2>&1; then
    :
  else
    cat "$log_file"
    echo "[portable-native-import] compile failed for $label" >&2
    exit 1
  fi
  printf '%s\n' "$log_file"
}

json_log="$(run_compile perf_json_portable \
  -cp test/perf/json -lib reflaxe.rust \
  -D reflaxe_rust_profile=portable \
  -D rust_no_build \
  -D rust_output=$cache_dir/out_json \
  -main Main)"

if grep -q 'portable contract imported native target modules: rust\.Ref' "$json_log"; then
  cat "$json_log"
  echo "[portable-native-import] unexpected framework native helper warning for portable haxe.Json path" >&2
  exit 1
fi

adapter_log="$(run_compile native_adapter_portable \
  -cp test/snapshot/rust_reflaxe_std_adapters -lib reflaxe.rust \
  -D reflaxe_rust_profile=portable \
  -D rust_no_build \
  -D rust_output=$cache_dir/out_adapter \
  -main Main)"

if ! grep -q 'portable contract imported native target modules: rust\.adapters\.ReflaxeStdAdapters' "$adapter_log"; then
  cat "$adapter_log"
  echo "[portable-native-import] missing user-authored native import warning for portable adapter import" >&2
  exit 1
fi

echo "[portable-native-import] ok"
