#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

run_negative_case() {
	local fixture_rel="$1"
	local expected_regex="$2"
	local failure_label="$3"
	local fixture_dir="$root_dir/$fixture_rel"
	local log_file="$fixture_dir/.compile.log"

	rm -rf "$fixture_dir/out"
	rm -f "$log_file"

	set +e
	(cd "$fixture_dir" && haxe compile.hxml) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -eq 0 ]]; then
		echo "[metal-policy] error: expected compile failure for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if ! match_regex "$expected_regex" "$log_file"; then
		echo "[metal-policy] error: compile failed, but expected diagnostic was not found for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	rm -f "$log_file"
	rm -rf "$fixture_dir/out"
}

run_negative_case "test/negative/metal_raw_rust" 'Strict mode forbids `__rust__\(\)` code injection in application code' \
	'raw __rust__ in app code under metal profile'
run_negative_case "test/negative/metal_reflect" 'metal profile forbids reflection modules' \
	'Reflect usage under metal profile'
run_negative_case "test/negative/profile_removed_idiomatic" 'Unknown `-D reflaxe_rust_profile=idiomatic`\. Expected portable\|metal\.' \
	'idiomatic profile selector removed'
run_negative_case "test/negative/profile_removed_rusty" 'Unknown `-D reflaxe_rust_profile=rusty`\. Expected portable\|metal\.' \
	'rusty profile selector removed'

echo "[metal-policy] ok"
