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

match_count() {
	local pattern="$1"
	local file="$2"
	if [[ "$use_rg" -eq 1 ]]; then
		rg -c -- "$pattern" "$file"
	else
		grep -Ec -- "$pattern" "$file"
	fi
}

tree_match_regex() {
	local pattern="$1"
	local dir="$2"
	if [[ "$use_rg" -eq 1 ]]; then
		rg -q -- "$pattern" "$dir"
	else
		grep -ERq -- "$pattern" "$dir"
	fi
}

run_warning_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local expected_regex="$3"
	local expected_count="$4"
	local failure_label="$5"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_policy_warning"
	local log_file="$fixture_dir/.compile.log"

	rm -rf "$out_dir"
	rm -f "$log_file"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_policy_warning) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if ! match_regex "$expected_regex" "$log_file"; then
		echo "[metal-policy] error: expected warning was not found for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	local found_count
	found_count="$(match_count "$expected_regex" "$log_file")"
	if [[ "$found_count" != "$expected_count" ]]; then
		echo "[metal-policy] error: expected ${expected_count} warning match(es) for ${failure_label}, found ${found_count}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	rm -f "$log_file"
	rm -rf "$out_dir"
}

run_no_hxrt_success_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_no_hxrt"
	local log_file="$fixture_dir/.compile.log"

	rm -rf "$out_dir"
	rm -f "$log_file"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_no_hxrt) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if [[ ! -f "$out_dir/Cargo.toml" ]]; then
		echo "[metal-policy] error: missing Cargo.toml for ${failure_label}."
		exit 1
	fi

	if match_regex 'hxrt[[:space:]]*=' "$out_dir/Cargo.toml"; then
		echo "[metal-policy] error: rust_no_hxrt case still emitted hxrt dependency for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/Cargo.toml"
		exit 1
	fi

	if [[ -d "$out_dir/hxrt" ]]; then
		echo "[metal-policy] error: rust_no_hxrt case still copied runtime crate for ${failure_label}."
		exit 1
	fi

	if tree_match_regex 'hxrt::|hxrt\.' "$out_dir/src"; then
		echo "[metal-policy] error: rust_no_hxrt case still references hxrt paths for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/src/main.rs"
		exit 1
	fi

	if ! (cd "$out_dir" && cargo build -q); then
		echo "[metal-policy] error: rust_no_hxrt case did not cargo-build for ${failure_label}."
		exit 1
	fi

	rm -f "$log_file"
	rm -rf "$out_dir"
}

run_negative_case "test/negative/metal_raw_rust" 'Strict mode forbids `__rust__\(\)` code injection in application code' \
	'raw __rust__ in app code under metal profile'
run_negative_case "test/negative/metal_reflect" 'metal profile forbids reflection/runtime-introspection modules' \
	'Reflect usage under metal profile'
run_negative_case "test/negative/metal_type_reflection" 'metal profile forbids reflection/runtime-introspection modules' \
	'Type runtime introspection under metal profile'
run_negative_case "test/negative/metal_dynamic_access" 'metal profile forbids haxe\.DynamicAccess runtime map semantics' \
	'haxe.DynamicAccess usage under metal profile'
run_negative_case "test/negative/metal_nullable_strings" 'metal profile does not allow -D rust_string_nullable in metal-clean mode' \
	'rust_string_nullable under metal profile'
run_negative_case "test/negative/metal_no_hxrt_requires_metal" '`-D rust_no_hxrt` currently requires `-D reflaxe_rust_profile=metal`\.' \
	'rust_no_hxrt requires metal profile'
run_negative_case "test/negative/metal_no_hxrt_runtime_boundary" '`-D rust_no_hxrt` violation in module' \
	'rust_no_hxrt rejects runtime-dependent output'
run_negative_case "test/negative/profile_removed_idiomatic" 'Unknown `-D reflaxe_rust_profile=idiomatic`\. Expected portable\|metal\.' \
	'idiomatic profile selector removed'
run_negative_case "test/negative/profile_removed_rusty" 'Unknown `-D reflaxe_rust_profile=rusty`\. Expected portable\|metal\.' \
	'rusty profile selector removed'
run_negative_case "test/negative/send_sync_borrow_capture" 'Rust concurrency contract violation: sys\.thread\.Thread\.create\(job\) captures `borrowed` with borrowed type `rust\.Ref<T>`' \
	'spawn closure captures borrow-only value under rust_send_sync_strict'
run_warning_case "test/negative/metal_dynamic_access" "compile.fallback.hxml" 'Rust profile contract: metal profile forbids haxe\.DynamicAccess runtime map semantics' \
	'1' 'haxe.DynamicAccess warning in explicit metal fallback mode'
run_warning_case "examples/hello" "compile.metal.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'1' 'single aggregated metal fallback warning'
run_no_hxrt_success_case "test/positive/metal_no_hxrt_minimal" "compile.hxml" \
	'rust_no_hxrt emits runtime-free minimal crate'

echo "[metal-policy] ok"
