#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture_dir="$root_dir/test/negative/metal_raw_rust"
log_file="$fixture_dir/.compile.log"

use_rg=0
if [[ "${REFLAXE_NO_RG:-0}" != "1" ]] && command -v rg >/dev/null 2>&1; then
	use_rg=1
fi

match_regex() {
	local pattern="$1"
	local file="$2"
	if [[ "$use_rg" -eq 1 ]]; then
		rg -q -- "$pattern" "$file"
	else
		grep -Eq -- "$pattern" "$file"
	fi
}

rm -rf "$fixture_dir/out"
rm -f "$log_file"

set +e
(cd "$fixture_dir" && haxe compile.hxml) >"$log_file" 2>&1
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
	echo "[metal-policy] error: expected compile failure for raw __rust__ in app code under metal profile."
	sed "s|$root_dir|.|g" "$log_file"
	exit 1
fi

if ! match_regex 'Strict mode forbids `__rust__\(\)` code injection in application code' "$log_file"; then
	echo "[metal-policy] error: compile failed, but strict-boundary diagnostic was not found."
	sed "s|$root_dir|.|g" "$log_file"
	exit 1
fi

rm -f "$log_file"
rm -rf "$fixture_dir/out"

echo "[metal-policy] ok"
