#!/usr/bin/env bash
set -euo pipefail

out="${1:-dist/reflaxe.rust.zip}"

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_abs="$root_dir/$out"

if ! command -v zip >/dev/null 2>&1; then
  echo "error: zip not found in PATH" >&2
  exit 2
fi

mkdir -p "$(dirname "$out_abs")"
rm -f "$out_abs"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe.rust-haxelib.XXXXXX")"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

cd "$root_dir"

cp -R src "$tmp/src"
cp -R vendor "$tmp/vendor"
cp -R std "$tmp/std"
cp -R runtime "$tmp/runtime"
cp -R haxe_libraries "$tmp/haxe_libraries"
cp .haxerc "$tmp/.haxerc"
cp package.json "$tmp/package.json"
cp package-lock.json "$tmp/package-lock.json"
cp extraParams.hxml "$tmp/extraParams.hxml"
cp haxelib.json "$tmp/haxelib.json"

(cd "$tmp" && zip -r -X "$out_abs" src vendor std runtime haxe_libraries .haxerc package.json package-lock.json extraParams.hxml haxelib.json >/dev/null)

echo "[package] wrote: $out"
