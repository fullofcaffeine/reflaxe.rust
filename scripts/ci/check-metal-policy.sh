#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
policy_timings_file="$(mktemp "${TMPDIR:-/tmp}/metal-policy-timings.XXXXXX")"

record_policy_timing() {
	local label="$1"
	local elapsed="$2"
	printf "%s\t%s\n" "$label" "$elapsed" >>"$policy_timings_file"
}

print_policy_timings() {
	if [[ ! -s "$policy_timings_file" ]]; then
		return 0
	fi

	echo "[metal-policy] case timings (seconds)"
	local total=0
	local label
	local elapsed
	while IFS=$'\t' read -r label elapsed; do
		printf "[metal-policy]   %s: %ss\n" "$label" "$elapsed"
		total=$((total + elapsed))
	done <"$policy_timings_file"
	printf "[metal-policy]   total: %ss\n" "$total"
}

finish_policy_case() {
	local label="$1"
	local start="$2"
	local elapsed=$((SECONDS - start))
	echo "[metal-policy] done: ${label} (${elapsed}s)"
	record_policy_timing "$label" "$elapsed"
}

on_exit() {
	local status=$?
	print_policy_timings
	rm -f "$policy_timings_file"
	return "$status"
}

trap on_exit EXIT

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
	local expected_location_regex="${4:-}"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local log_file="$fixture_dir/.compile.log"
	echo "[metal-policy] case: ${failure_label}"

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
	if [[ -n "$expected_location_regex" ]] && ! match_regex "$expected_location_regex" "$log_file"; then
		echo "[metal-policy] error: compile failed, but expected source-position diagnostic was not found for ${failure_label}."
		echo "[metal-policy] expected location regex: ${expected_location_regex}"
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	rm -f "$log_file"
	rm -rf "$fixture_dir/out"
	finish_policy_case "$failure_label" "$case_start"
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
	local expected_location_regex="${6:-}"
	local extra_define="${7:-}"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_policy_warning"
	local log_file="$fixture_dir/.compile.log"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file"

	local cmd=(haxe "$hxml_file" -D rust_no_build -D rust_output=out_policy_warning)
	if [[ -n "$extra_define" ]]; then
		cmd+=(-D "$extra_define")
	fi
	set +e
	(cd "$fixture_dir" && "${cmd[@]}") >"$log_file" 2>&1
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
	if [[ -n "$expected_location_regex" ]] && ! match_regex "$expected_location_regex" "$log_file"; then
		echo "[metal-policy] error: expected warning source-position diagnostic was not found for ${failure_label}."
		echo "[metal-policy] expected location regex: ${expected_location_regex}"
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	rm -f "$log_file"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_warning_case_absent() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local required_regex="$3"
	local forbidden_regex="$4"
	local expected_count="$5"
	local failure_label="$6"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_policy_warning_absent"
	local log_file="$fixture_dir/.compile_absent.log"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_policy_warning_absent) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if ! match_regex "$required_regex" "$log_file"; then
		echo "[metal-policy] error: expected required warning was not found for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	local found_count
	found_count="$(match_count "$required_regex" "$log_file")"
	if [[ "$found_count" != "$expected_count" ]]; then
		echo "[metal-policy] error: expected ${expected_count} required warning match(es) for ${failure_label}, found ${found_count}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if match_regex "$forbidden_regex" "$log_file"; then
		echo "[metal-policy] error: forbidden fallback marker found for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	rm -f "$log_file"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_optional_fallback_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local warning_regex="$3"
	local forbidden_regex="${4:-}"
	local failure_label="$5"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_policy_fallback_optional"
	local log_file="$fixture_dir/.compile_fallback_optional.log"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_policy_fallback_optional) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	local found_count
	if match_regex "$warning_regex" "$log_file"; then
		found_count="$(match_count "$warning_regex" "$log_file")"
	else
		found_count="0"
	fi
	if [[ "$found_count" == "0" ]]; then
		rm -f "$log_file"
		rm -rf "$out_dir"
		finish_policy_case "$failure_label" "$case_start"
		return
	fi

	if [[ "$found_count" != "1" ]]; then
		echo "[metal-policy] error: expected 0 or 1 fallback warning match(es) for ${failure_label}, found ${found_count}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if [[ -n "$forbidden_regex" ]] && match_regex "$forbidden_regex" "$log_file"; then
		echo "[metal-policy] error: forbidden fallback marker found for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	rm -f "$log_file"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_optional_fallback_group() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local warning_regex="$3"
	local failure_label="$4"
	shift 4
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_policy_fallback_group"
	local log_file="$fixture_dir/.compile_fallback_group.log"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_policy_fallback_group) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	local found_count
	if match_regex "$warning_regex" "$log_file"; then
		found_count="$(match_count "$warning_regex" "$log_file")"
	else
		found_count="0"
	fi
	if [[ "$found_count" == "0" ]]; then
		rm -f "$log_file"
		rm -rf "$out_dir"
		finish_policy_case "$failure_label" "$case_start"
		return
	fi

	if [[ "$found_count" != "1" ]]; then
		echo "[metal-policy] error: expected 0 or 1 fallback warning match(es) for ${failure_label}, found ${found_count}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	while [[ "$#" -gt 0 ]]; do
		local forbidden_regex="$1"
		local assertion_label="$2"
		shift 2
		if [[ -n "$forbidden_regex" ]] && match_regex "$forbidden_regex" "$log_file"; then
			echo "[metal-policy] error: forbidden fallback marker found for ${assertion_label}."
			sed "s|$root_dir|.|g" "$log_file"
			exit 1
		fi
	done

	rm -f "$log_file"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_report_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_a="$fixture_dir/out_policy_report_a"
	local out_b="$fixture_dir/out_policy_report_b"
	local log_a="$fixture_dir/.compile_report_a.log"
	local log_b="$fixture_dir/.compile_report_b.log"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_a" "$out_b"
	rm -f "$log_a" "$log_b"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_policy_report_a) >"$log_a" 2>&1
	local status_a=$?
	set -e
	if [[ "$status_a" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label} (run A)."
		sed "s|$root_dir|.|g" "$log_a"
		exit 1
	fi

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_policy_report_b) >"$log_b" 2>&1
	local status_b=$?
	set -e
	if [[ "$status_b" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label} (run B)."
		sed "s|$root_dir|.|g" "$log_b"
		exit 1
	fi

	local json_a="$out_a/metal_report.json"
	local md_a="$out_a/metal_report.md"
	local json_b="$out_b/metal_report.json"
	local md_b="$out_b/metal_report.md"

	if [[ ! -f "$json_a" || ! -f "$md_a" ]]; then
		echo "[metal-policy] error: expected metal viability report artifacts for ${failure_label} (run A)."
		exit 1
	fi
	if [[ ! -f "$json_b" || ! -f "$md_b" ]]; then
		echo "[metal-policy] error: expected metal viability report artifacts for ${failure_label} (run B)."
		exit 1
	fi

	if ! match_regex '"profile":[[:space:]]*"metal"' "$json_a"; then
		echo "[metal-policy] error: metal_report.json missing profile marker for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"overallScore":[[:space:]]*[0-9]+' "$json_a"; then
		echo "[metal-policy] error: metal_report.json missing overallScore for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"issueClasses":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: metal_report.json missing issueClasses for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"id":[[:space:]]*"dynamic_access"' "$json_a"; then
		echo "[metal-policy] error: metal_report.json missing expected dynamic_access blocker for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"id":[[:space:]]*"dynamic_boundary"' "$json_a"; then
		echo "[metal-policy] error: metal_report.json missing expected dynamic_boundary issue class for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '^# Metal Viability Report' "$md_a"; then
		echo "[metal-policy] error: metal_report.md missing title for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Issue classes' "$md_a"; then
		echo "[metal-policy] error: metal_report.md missing issue classes section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '`dynamic_boundary/dynamic_access`' "$md_a"; then
		echo "[metal-policy] error: metal_report.md missing expected blocker entry for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi

	if ! cmp -s "$json_a" "$json_b"; then
		echo "[metal-policy] error: metal_report.json is non-deterministic across runs for ${failure_label}."
		diff -u "$json_a" "$json_b" || true
		exit 1
	fi
	if ! cmp -s "$md_a" "$md_b"; then
		echo "[metal-policy] error: metal_report.md is non-deterministic across runs for ${failure_label}."
		diff -u "$md_a" "$md_b" || true
		exit 1
	fi

	rm -f "$log_a" "$log_b"
	rm -rf "$out_a" "$out_b"
	finish_policy_case "$failure_label" "$case_start"
}

run_contract_report_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local expected_contract="$3"
	local failure_label="$4"
	local expected_strict_boundary="${5:-}"
	local expected_strict_examples="${6:-}"
	local expected_metal_fallback_allowed="${7:-}"
	local expected_metal_contract_hard_error="${8:-}"
	local expected_no_hxrt="${9:-}"
	local expected_async_enabled="${10:-}"
	local expected_nullable_strings="${11:-}"
	local expected_json_patterns="${12:-}"
	local expected_markdown_patterns="${13:-}"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_a="$fixture_dir/out_contract_report_a"
	local out_b="$fixture_dir/out_contract_report_b"
	local log_a="$fixture_dir/.compile_profile_a.log"
	local log_b="$fixture_dir/.compile_profile_b.log"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_a" "$out_b"
	rm -f "$log_a" "$log_b"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_contract_report -D rust_output=out_contract_report_a) >"$log_a" 2>&1
	local status_a=$?
	set -e
	if [[ "$status_a" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label} (run A)."
		sed "s|$root_dir|.|g" "$log_a"
		exit 1
	fi

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_contract_report -D rust_output=out_contract_report_b) >"$log_b" 2>&1
	local status_b=$?
	set -e
	if [[ "$status_b" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label} (run B)."
		sed "s|$root_dir|.|g" "$log_b"
		exit 1
	fi

	local json_a="$out_a/contract_report.json"
	local md_a="$out_a/contract_report.md"
	local json_b="$out_b/contract_report.json"
	local md_b="$out_b/contract_report.md"

	if [[ ! -f "$json_a" || ! -f "$md_a" ]]; then
		echo "[metal-policy] error: expected contract report artifacts for ${failure_label} (run A)."
		exit 1
	fi
	if [[ ! -f "$json_b" || ! -f "$md_b" ]]; then
		echo "[metal-policy] error: expected contract report artifacts for ${failure_label} (run B)."
		exit 1
	fi

	if ! match_regex '"schemaVersion":[[:space:]]*6' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing schemaVersion for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"backendId":[[:space:]]*"reflaxe\.rust"' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing backendId for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex "\"contract\":[[:space:]]*\"${expected_contract}\"" "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing expected contract for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"familyStdPin":[[:space:]]*\{' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing familyStdPin object for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"pinFile":[[:space:]]*"family/family_std_pin\.json"' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing familyStdPin.pinFile for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"strictBoundary":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing strictBoundary for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"strictExamples":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing strictExamples for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"metalFallbackAllowed":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing metalFallbackAllowed for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"metalContractHardError":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing metalContractHardError for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"noHxrt":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing noHxrt for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"asyncEnabled":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing asyncEnabled for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"nullableStrings":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing nullableStrings for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"portableNativeImportStrict":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing portableNativeImportStrict for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"portableNativeImportsDetected":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing portableNativeImportsDetected for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"nativeImportHits":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing nativeImportHits array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"nativeImportHitsTyped":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing nativeImportHitsTyped array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"consumedSurfaces":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing consumedSurfaces array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"nativeRepresentationPlan":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing nativeRepresentationPlan array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"warnings":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing warnings array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"errors":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: contract_report.json missing errors array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '^# Contract Report' "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing title for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- backend id: \`reflaxe\.rust\`" "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing backend id summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- contract: \`${expected_contract}\`" "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing contract summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- family std pin file: \`family/family_std_pin\.json\`" "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing family std pin summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Warnings' "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing warnings section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Errors' "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing errors section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- strict boundary: \`(yes|no)\`" "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing strict-boundary summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- no hxrt: \`(yes|no)\`" "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing no-hxrt summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- portable native import strict: \`(yes|no)\`" "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing portable-native-import-strict summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- portable native imports detected: \`(yes|no)\`" "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing portable-native-imports-detected summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Native Import Hits' "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing native-import-hits section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Typed Native Import Hits' "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing typed-native-import-hits section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Consumed Surfaces' "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing consumed-surfaces section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Native Representation Plan' "$md_a"; then
		echo "[metal-policy] error: contract_report.md missing native-representation-plan section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi

	if [[ -n "$expected_strict_boundary" ]] && ! match_regex "\"strictBoundary\":[[:space:]]*${expected_strict_boundary}" "$json_a"; then
		echo "[metal-policy] error: contract_report.json strictBoundary mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_strict_examples" ]] && ! match_regex "\"strictExamples\":[[:space:]]*${expected_strict_examples}" "$json_a"; then
		echo "[metal-policy] error: contract_report.json strictExamples mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_metal_fallback_allowed" ]] && ! match_regex "\"metalFallbackAllowed\":[[:space:]]*${expected_metal_fallback_allowed}" "$json_a"; then
		echo "[metal-policy] error: contract_report.json metalFallbackAllowed mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_metal_contract_hard_error" ]] \
		&& ! match_regex "\"metalContractHardError\":[[:space:]]*${expected_metal_contract_hard_error}" "$json_a"; then
		echo "[metal-policy] error: contract_report.json metalContractHardError mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_no_hxrt" ]] && ! match_regex "\"noHxrt\":[[:space:]]*${expected_no_hxrt}" "$json_a"; then
		echo "[metal-policy] error: contract_report.json noHxrt mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_async_enabled" ]] && ! match_regex "\"asyncEnabled\":[[:space:]]*${expected_async_enabled}" "$json_a"; then
		echo "[metal-policy] error: contract_report.json asyncEnabled mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_nullable_strings" ]] && ! match_regex "\"nullableStrings\":[[:space:]]*${expected_nullable_strings}" "$json_a"; then
		echo "[metal-policy] error: contract_report.json nullableStrings mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_json_patterns" ]]; then
		while IFS= read -r expected_pattern; do
			[[ -z "$expected_pattern" ]] && continue
			if ! match_regex "$expected_pattern" "$json_a"; then
				echo "[metal-policy] error: contract_report.json missing expected pattern for ${failure_label}: ${expected_pattern}"
				sed "s|$root_dir|.|g" "$json_a"
				exit 1
			fi
		done <<<"$expected_json_patterns"
	fi
	if [[ -n "$expected_markdown_patterns" ]]; then
		while IFS= read -r expected_pattern; do
			[[ -z "$expected_pattern" ]] && continue
			if ! match_regex "$expected_pattern" "$md_a"; then
				echo "[metal-policy] error: contract_report.md missing expected pattern for ${failure_label}: ${expected_pattern}"
				sed "s|$root_dir|.|g" "$md_a"
				exit 1
			fi
		done <<<"$expected_markdown_patterns"
	fi

	if ! cmp -s "$json_a" "$json_b"; then
		echo "[metal-policy] error: contract_report.json is non-deterministic across runs for ${failure_label}."
		diff -u "$json_a" "$json_b" || true
		exit 1
	fi
	if ! cmp -s "$md_a" "$md_b"; then
		echo "[metal-policy] error: contract_report.md is non-deterministic across runs for ${failure_label}."
		diff -u "$md_a" "$md_b" || true
		exit 1
	fi

	rm -f "$log_a" "$log_b"
	rm -rf "$out_a" "$out_b"
	finish_policy_case "$failure_label" "$case_start"
}

run_runtime_plan_report_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local expected_contract="$3"
	local expected_mode="$4"
	local failure_label="$5"
	local extra_define="${6:-}"
	local expected_reason_regex="${7:-}"
	local expected_reason_regex_2="${8:-}"
	local expected_runtime_regex="${9:-}"
	local expected_runtime_regex_2="${10:-}"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_a="$fixture_dir/out_runtime_plan_a"
	local out_b="$fixture_dir/out_runtime_plan_b"
	local log_a="$fixture_dir/.compile_runtime_plan_a.log"
	local log_b="$fixture_dir/.compile_runtime_plan_b.log"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_a" "$out_b"
	rm -f "$log_a" "$log_b"

	local cmd_a=(haxe "$hxml_file" -D rust_no_build -D rust_runtime_plan_report -D rust_output=out_runtime_plan_a)
	local cmd_b=(haxe "$hxml_file" -D rust_no_build -D rust_runtime_plan_report -D rust_output=out_runtime_plan_b)
	if [[ -n "$extra_define" ]]; then
		cmd_a+=(-D "$extra_define")
		cmd_b+=(-D "$extra_define")
	fi

	set +e
	(cd "$fixture_dir" && "${cmd_a[@]}") >"$log_a" 2>&1
	local status_a=$?
	set -e
	if [[ "$status_a" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label} (run A)."
		sed "s|$root_dir|.|g" "$log_a"
		exit 1
	fi

	set +e
	(cd "$fixture_dir" && "${cmd_b[@]}") >"$log_b" 2>&1
	local status_b=$?
	set -e
	if [[ "$status_b" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label} (run B)."
		sed "s|$root_dir|.|g" "$log_b"
		exit 1
	fi

	local json_a="$out_a/runtime_plan.json"
	local md_a="$out_a/runtime_plan.md"
	local json_b="$out_b/runtime_plan.json"
	local md_b="$out_b/runtime_plan.md"

	if [[ ! -f "$json_a" || ! -f "$md_a" ]]; then
		echo "[metal-policy] error: expected runtime plan artifacts for ${failure_label} (run A)."
		exit 1
	fi
	if [[ ! -f "$json_b" || ! -f "$md_b" ]]; then
		echo "[metal-policy] error: expected runtime plan artifacts for ${failure_label} (run B)."
		exit 1
	fi

	if ! match_regex '"schemaVersion":[[:space:]]*4' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing schemaVersion for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"backendId":[[:space:]]*"reflaxe\.rust"' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing backendId for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"runtimeId":[[:space:]]*"hxrt"' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing runtimeId for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex "\"contract\":[[:space:]]*\"${expected_contract}\"" "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing expected contract for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"familyStdPin":[[:space:]]*\{' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing familyStdPin object for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"pinFile":[[:space:]]*"family/family_std_pin\.json"' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing familyStdPin.pinFile for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex "\"mode\":[[:space:]]*\"${expected_mode}\"" "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing expected mode for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"selectedFeatures":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing selectedFeatures for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"manualFeatures":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing manualFeatures for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"noHxrt":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing noHxrt for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"useDefaultFeatures":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing useDefaultFeatures for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"inferenceDisabled":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing inferenceDisabled for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"reasons":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing reasons array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"runtimeRequirements":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing runtimeRequirements array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"fallbackSummary":[[:space:]]*\{' "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing fallbackSummary object for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_runtime_regex" ]] && ! match_regex "$expected_runtime_regex" "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing expected runtime requirement pattern for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_runtime_regex_2" ]] && ! match_regex "$expected_runtime_regex_2" "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing second expected runtime requirement pattern for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_reason_regex" ]] && ! match_regex "$expected_reason_regex" "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing expected reason pattern for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_reason_regex_2" ]] && ! match_regex "$expected_reason_regex_2" "$json_a"; then
		echo "[metal-policy] error: runtime_plan.json missing second expected reason pattern for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ "$expected_mode" == "no_hxrt" ]]; then
		if ! match_regex '"noHxrt":[[:space:]]*true' "$json_a"; then
			echo "[metal-policy] error: runtime_plan.json expected noHxrt=true for no_hxrt mode (${failure_label})."
			sed "s|$root_dir|.|g" "$json_a"
			exit 1
		fi
		if ! match_regex '"hxrtDependencyLine":[[:space:]]*""' "$json_a"; then
			echo "[metal-policy] error: runtime_plan.json expected empty dependency line for no_hxrt mode (${failure_label})."
			sed "s|$root_dir|.|g" "$json_a"
			exit 1
		fi
	else
		if ! match_regex '"noHxrt":[[:space:]]*false' "$json_a"; then
			echo "[metal-policy] error: runtime_plan.json expected noHxrt=false for ${expected_mode} mode (${failure_label})."
			sed "s|$root_dir|.|g" "$json_a"
			exit 1
		fi
	fi
	if [[ "$expected_mode" == "default_features" ]]; then
		if ! match_regex '"useDefaultFeatures":[[:space:]]*true' "$json_a"; then
			echo "[metal-policy] error: runtime_plan.json expected useDefaultFeatures=true for default_features mode (${failure_label})."
			sed "s|$root_dir|.|g" "$json_a"
			exit 1
		fi
	else
		if ! match_regex '"useDefaultFeatures":[[:space:]]*false' "$json_a"; then
			echo "[metal-policy] error: runtime_plan.json expected useDefaultFeatures=false for ${expected_mode} mode (${failure_label})."
			sed "s|$root_dir|.|g" "$json_a"
			exit 1
		fi
	fi
	if ! match_regex '^# Runtime Plan' "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing title for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- backend id: \`reflaxe\.rust\`" "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing backend id summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- runtime id: \`hxrt\`" "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing runtime id summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- contract: \`${expected_contract}\`" "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing contract summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- family std pin file: \`family/family_std_pin\.json\`" "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing family std pin summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Selected features' "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing selected features section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Manual features' "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing manual features section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Feature reasons' "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing feature reasons section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Runtime requirements' "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing runtime requirements section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Fallback summary' "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing fallback summary section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Dependency line' "$md_a"; then
		echo "[metal-policy] error: runtime_plan.md missing dependency line section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi

	if ! cmp -s "$json_a" "$json_b"; then
		echo "[metal-policy] error: runtime_plan.json is non-deterministic across runs for ${failure_label}."
		diff -u "$json_a" "$json_b" || true
		exit 1
	fi
	if ! cmp -s "$md_a" "$md_b"; then
		echo "[metal-policy] error: runtime_plan.md is non-deterministic across runs for ${failure_label}."
		diff -u "$md_a" "$md_b" || true
		exit 1
	fi

	rm -f "$log_a" "$log_b"
	rm -rf "$out_a" "$out_b"
	finish_policy_case "$failure_label" "$case_start"
}

run_optimizer_plan_report_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local expected_contract="$3"
	local failure_label="$4"
	local expected_json_regex="${5:-}"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_a="$fixture_dir/out_optimizer_plan_a"
	local out_b="$fixture_dir/out_optimizer_plan_b"
	local log_a="$fixture_dir/.compile_optimizer_plan_a.log"
	local log_b="$fixture_dir/.compile_optimizer_plan_b.log"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_a" "$out_b"
	rm -f "$log_a" "$log_b"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_optimizer_plan_report -D rust_output=out_optimizer_plan_a) >"$log_a" 2>&1
	local status_a=$?
	set -e
	if [[ "$status_a" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label} (run A)."
		sed "s|$root_dir|.|g" "$log_a"
		exit 1
	fi

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_optimizer_plan_report -D rust_output=out_optimizer_plan_b) >"$log_b" 2>&1
	local status_b=$?
	set -e
	if [[ "$status_b" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label} (run B)."
		sed "s|$root_dir|.|g" "$log_b"
		exit 1
	fi

	local json_a="$out_a/optimizer_plan.json"
	local md_a="$out_a/optimizer_plan.md"
	local json_b="$out_b/optimizer_plan.json"
	local md_b="$out_b/optimizer_plan.md"

	if [[ ! -f "$json_a" || ! -f "$md_a" ]]; then
		echo "[metal-policy] error: expected optimizer plan artifacts for ${failure_label} (run A)."
		exit 1
	fi
	if [[ ! -f "$json_b" || ! -f "$md_b" ]]; then
		echo "[metal-policy] error: expected optimizer plan artifacts for ${failure_label} (run B)."
		exit 1
	fi

	if ! match_regex '"schemaVersion":[[:space:]]*2' "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing schemaVersion for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"backendId":[[:space:]]*"reflaxe\.rust"' "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing backendId for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex "\"contract\":[[:space:]]*\"${expected_contract}\"" "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing expected contract for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"familyStdPin":[[:space:]]*\{' "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing familyStdPin object for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"pinFile":[[:space:]]*"family/family_std_pin\.json"' "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing familyStdPin.pinFile for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"executedPasses":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing executedPasses for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"applied":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing applied metrics for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"skipped":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing skipped metrics for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"cloneElisions":[[:space:]]*[0-9]+' "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing cloneElisions aggregate for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"loopOptimizations":[[:space:]]*[0-9]+' "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing loopOptimizations aggregate for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '^# Optimizer Plan' "$md_a"; then
		echo "[metal-policy] error: optimizer_plan.md missing title for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- contract: \`${expected_contract}\`" "$md_a"; then
		echo "[metal-policy] error: optimizer_plan.md missing contract summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- family std pin file: \`family/family_std_pin\.json\`" "$md_a"; then
		echo "[metal-policy] error: optimizer_plan.md missing family std pin summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Applied optimizations' "$md_a"; then
		echo "[metal-policy] error: optimizer_plan.md missing applied section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Skipped optimizations' "$md_a"; then
		echo "[metal-policy] error: optimizer_plan.md missing skipped section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if [[ -n "$expected_json_regex" ]] && ! match_regex "$expected_json_regex" "$json_a"; then
		echo "[metal-policy] error: optimizer_plan.json missing expected metric pattern for ${failure_label}."
		echo "[metal-policy] pattern: $expected_json_regex"
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi

	if ! cmp -s "$json_a" "$json_b"; then
		echo "[metal-policy] error: optimizer_plan.json is non-deterministic across runs for ${failure_label}."
		diff -u "$json_a" "$json_b" || true
		exit 1
	fi
	if ! cmp -s "$md_a" "$md_b"; then
		echo "[metal-policy] error: optimizer_plan.md is non-deterministic across runs for ${failure_label}."
		diff -u "$md_a" "$md_b" || true
		exit 1
	fi

	rm -f "$log_a" "$log_b"
	rm -rf "$out_a" "$out_b"
	finish_policy_case "$failure_label" "$case_start"
}

run_portable_facade_output_shape_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_output_shape"
	local log_file="$fixture_dir/.compile_output_shape.log"
	local main_rs="$out_dir/src/main.rs"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_output_shape) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if [[ ! -f "$main_rs" ]]; then
		echo "[metal-policy] error: missing generated src/main.rs for ${failure_label}."
		exit 1
	fi

	local required_patterns=(
		'fn option_score\(value: Option<i32>\) -> i32'
		'fn result_score\(value: Result<i32, i32>\) -> i32'
		'let maybe: Option<i32> = Option::Some\(3\);'
		'let fallback: Option<i32> = Option::None;'
		'let done: Result<i32, i32> = Result::Ok\(5\);'
		'let fail: Result<i32, i32> = Result::Err\(2\);'
		'Option::Some'
		'Option::None'
		'Result::Ok'
		'Result::Err'
	)
	for pattern in "${required_patterns[@]}"; do
		if ! match_regex "$pattern" "$main_rs"; then
			echo "[metal-policy] error: generated user module missing native facade output-shape pattern for ${failure_label}: ${pattern}"
			sed "s|$root_dir|.|g" "$main_rs"
			exit 1
		fi
	done

	local forbidden_patterns=(
		'hxrt::dynamic'
		'hxrt::array'
		'__rust__'
		'ERaw'
	)
	for pattern in "${forbidden_patterns[@]}"; do
		if match_regex "$pattern" "$main_rs"; then
			echo "[metal-policy] error: generated user module contains forbidden facade output-shape pattern for ${failure_label}: ${pattern}"
			sed "s|$root_dir|.|g" "$main_rs"
			exit 1
		fi
	done

	if ! (cd "$out_dir" && cargo build -q); then
		echo "[metal-policy] error: generated portable facade crate did not cargo-build for ${failure_label}."
		exit 1
	fi

	rm -f "$log_file"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_slice_view_output_shape_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_slice_view_shape"
	local log_file="$fixture_dir/.compile_slice_view_shape.log"
	local main_rs="$out_dir/src/main.rs"
	local bridge_rs="$out_dir/src/array_borrow_tools.rs"
	local array_rs="$out_dir/hxrt/src/array.rs"
	local slice_body="$out_dir/.with_slice.body"
	local mut_slice_body="$out_dir/.with_mut_slice.body"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_slice_view_shape) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	for required_file in "$main_rs" "$bridge_rs" "$array_rs"; do
		if [[ ! -f "$required_file" ]]; then
			echo "[metal-policy] error: missing generated file for ${failure_label}: ${required_file#$root_dir/}"
			exit 1
		fi
	done

	local main_patterns=(
		'crate::rust_array_borrow::ArrayBorrow::with_slice\(xs\.clone\(\),'
		'crate::rust_array_borrow::ArrayBorrow::with_mut_slice\(xs\.clone\(\),'
		'let s: &\[i32\] = _hx_slice;'
		'let s: &mut \[i32\] = _hx_slice;'
	)
	for pattern in "${main_patterns[@]}"; do
		if ! match_regex "$pattern" "$main_rs"; then
			echo "[metal-policy] error: generated main missing slice-view call pattern for ${failure_label}: ${pattern}"
			sed "s|$root_dir|.|g" "$main_rs"
			exit 1
		fi
	done

	local bridge_patterns=(
		'hxrt::array::with_slice\(array, f\)'
		'hxrt::array::with_mut_slice\(array, f\)'
	)
	for pattern in "${bridge_patterns[@]}"; do
		if ! match_regex "$pattern" "$bridge_rs"; then
			echo "[metal-policy] error: generated ArrayBorrow bridge missing no-clone delegation for ${failure_label}: ${pattern}"
			sed "s|$root_dir|.|g" "$bridge_rs"
			exit 1
		fi
	done

	sed -n '/pub fn with_slice/,/^}/p' "$array_rs" >"$slice_body"
	sed -n '/pub fn with_mut_slice/,/^}/p' "$array_rs" >"$mut_slice_body"
	if [[ ! -s "$slice_body" || ! -s "$mut_slice_body" ]]; then
		echo "[metal-policy] error: could not extract HXRT slice-view helper bodies for ${failure_label}."
		sed "s|$root_dir|.|g" "$array_rs"
		exit 1
	fi

	local slice_patterns=(
		'let borrow = array\.inner\.borrow\(\);'
		'f\(borrow\.as_slice\(\)\)'
	)
	for pattern in "${slice_patterns[@]}"; do
		if ! match_regex "$pattern" "$slice_body"; then
			echo "[metal-policy] error: HXRT immutable slice helper missing borrowed-view pattern for ${failure_label}: ${pattern}"
			cat "$slice_body"
			exit 1
		fi
	done

	local mut_slice_patterns=(
		'let mut borrow = array\.inner\.borrow_mut\(\);'
		'f\(borrow\.as_mut_slice\(\)\)'
	)
	for pattern in "${mut_slice_patterns[@]}"; do
		if ! match_regex "$pattern" "$mut_slice_body"; then
			echo "[metal-policy] error: HXRT mutable slice helper missing borrowed-view pattern for ${failure_label}: ${pattern}"
			cat "$mut_slice_body"
			exit 1
		fi
	done

	local forbidden_body_patterns=(
		'clone\('
		'to_vec\('
		'Array::from_vec'
		'Vec::from'
		'\.cloned\('
	)
	for pattern in "${forbidden_body_patterns[@]}"; do
		if match_regex "$pattern" "$slice_body" || match_regex "$pattern" "$mut_slice_body"; then
			echo "[metal-policy] error: HXRT slice-view helper materializes storage for ${failure_label}: ${pattern}"
			echo "[metal-policy] with_slice body:"
			cat "$slice_body"
			echo "[metal-policy] with_mut_slice body:"
			cat "$mut_slice_body"
			exit 1
		fi
	done

	if ! (cd "$out_dir" && cargo fmt -q); then
		echo "[metal-policy] error: generated slice-view crate could not be rustfmt-formatted for ${failure_label}."
		exit 1
	fi
	if ! (cd "$out_dir" && cargo build -q); then
		echo "[metal-policy] error: generated slice-view crate did not cargo-build for ${failure_label}."
		exit 1
	fi

	rm -f "$log_file"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_no_hxrt_success_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_no_hxrt"
	local log_file="$fixture_dir/.compile.log"
	echo "[metal-policy] case: ${failure_label}"

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
	finish_policy_case "$failure_label" "$case_start"
}

run_native_file_output_shape_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_native_file_shape"
	local log_file="$fixture_dir/.compile_native_file_shape.log"
	local native_file_rs="$out_dir/src/native_file_tools.rs"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_native_file_shape) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if [[ ! -f "$native_file_rs" ]]; then
		echo "[metal-policy] error: missing native_file_tools.rs for ${failure_label}."
		exit 1
	fi
	if match_regex 'hxrt[[:space:]]*=' "$out_dir/Cargo.toml"; then
		echo "[metal-policy] error: native file no-hxrt fixture emitted hxrt dependency for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/Cargo.toml"
		exit 1
	fi
	if [[ -d "$out_dir/hxrt" ]]; then
		echo "[metal-policy] error: native file no-hxrt fixture copied runtime crate for ${failure_label}."
		exit 1
	fi
	if tree_match_regex 'hxrt::|hxrt\.|Dynamic|__rust__|ERaw|FileHandle|file_native|sys_io_' "$out_dir/src"; then
		echo "[metal-policy] error: native file fixture used runtime, Dynamic, raw, or portable sys/file paths for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/src/main.rs"
		exit 1
	fi
	if ! match_regex 'std::fs::write' "$native_file_rs"; then
		echo "[metal-policy] error: native file fixture missing direct std::fs::write helper for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_file_rs"
		exit 1
	fi
	if ! match_regex 'std::fs::read_to_string' "$native_file_rs"; then
		echo "[metal-policy] error: native file fixture missing direct std::fs::read_to_string helper for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_file_rs"
		exit 1
	fi
	if ! match_regex 'std::fs::remove_file' "$native_file_rs"; then
		echo "[metal-policy] error: native file fixture missing direct std::fs::remove_file helper for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_file_rs"
		exit 1
	fi
	if ! match_regex 'Result<[^>]*String' "$native_file_rs"; then
		echo "[metal-policy] error: native file fixture should expose Result<_, String> error boundaries for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_file_rs"
		exit 1
	fi
	if ! (cd "$out_dir" && cargo build -q); then
		echo "[metal-policy] error: native file no-hxrt fixture did not cargo-build for ${failure_label}."
		exit 1
	fi

	rm -f "$log_file"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_native_tcp_output_shape_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_native_tcp_shape"
	local log_file="$fixture_dir/.compile_native_tcp_shape.log"
	local run_log="$fixture_dir/.run_native_tcp_shape.log"
	local native_tcp_rs="$out_dir/src/native_tcp_tools.rs"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file" "$run_log"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_native_tcp_shape) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if [[ ! -f "$native_tcp_rs" ]]; then
		echo "[metal-policy] error: missing native_tcp_tools.rs for ${failure_label}."
		exit 1
	fi
	if match_regex 'hxrt[[:space:]]*=' "$out_dir/Cargo.toml"; then
		echo "[metal-policy] error: native TCP no-hxrt fixture emitted hxrt dependency for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/Cargo.toml"
		exit 1
	fi
	if [[ -d "$out_dir/hxrt" ]]; then
		echo "[metal-policy] error: native TCP no-hxrt fixture copied runtime crate for ${failure_label}."
		exit 1
	fi
	if tree_match_regex 'hxrt::|hxrt\.|Dynamic|__rust__|ERaw|SocketHandle|socket_native|sys_net' "$out_dir/src"; then
		echo "[metal-policy] error: native TCP fixture used runtime, Dynamic, raw, or portable sys/socket paths for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/src/main.rs"
		exit 1
	fi
	if ! match_regex 'use std::net::\{Shutdown, TcpListener as StdTcpListener, TcpStream as StdTcpStream\}' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture missing direct std::net imports for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub struct NativeTcp' "$native_tcp_rs" || ! match_regex 'pub struct TcpListener' "$native_tcp_rs" || ! match_regex 'pub struct TcpStream' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture missing typed native TCP structs for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'listener: StdTcpListener' "$native_tcp_rs" || ! match_regex 'stream: StdTcpStream' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture should wrap owned std::net listener/stream handles for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'StdTcpListener::bind\(\("127\.0\.0\.1", port\)\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture missing direct localhost TcpListener::bind for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'StdTcpStream::connect\(\("127\.0\.0\.1", port\)\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture missing direct localhost TcpStream::connect for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn localPort\(&self\) -> Result<i32, String>' "$native_tcp_rs" || ! match_regex 'local_addr\(\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture missing localPort/local_addr wiring for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn accept\(&self\) -> Result<TcpStream, String>' "$native_tcp_rs" || ! match_regex '\.accept\(\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture missing listener accept wiring for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn writeUtf8AndShutdownWrite\(&mut self, payload: String\) -> Result<bool, String>' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture missing mutating write/shutdown helper for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'write_all\(payload\.as_bytes\(\)\)' "$native_tcp_rs" || ! match_regex 'shutdown\(Shutdown::Write\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture missing direct write_all plus Shutdown::Write for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn readToString\(&mut self\) -> Result<String, String>' "$native_tcp_rs" || ! match_regex 'read_to_string\(&mut output\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture missing mutating read_to_string helper for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'Result<[^>]*String' "$native_tcp_rs"; then
		echo "[metal-policy] error: native TCP fixture should expose Result<_, String> error boundaries for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! (cd "$out_dir" && cargo build -q); then
		echo "[metal-policy] error: native TCP no-hxrt fixture did not cargo-build for ${failure_label}."
		exit 1
	fi
	if ! (cd "$out_dir" && cargo run -q) >"$run_log" 2>&1; then
		echo "[metal-policy] error: native TCP no-hxrt fixture did not cargo-run for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi
	if [[ -s "$run_log" ]]; then
		echo "[metal-policy] error: native TCP fixture produced unexpected stdout/stderr for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi

	rm -f "$log_file" "$run_log"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_native_udp_output_shape_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_native_udp_shape"
	local log_file="$fixture_dir/.compile_native_udp_shape.log"
	local run_log="$fixture_dir/.run_native_udp_shape.log"
	local native_udp_rs="$out_dir/src/native_udp_tools.rs"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file" "$run_log"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_native_udp_shape) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if [[ ! -f "$native_udp_rs" ]]; then
		echo "[metal-policy] error: missing native_udp_tools.rs for ${failure_label}."
		exit 1
	fi
	if match_regex 'hxrt[[:space:]]*=' "$out_dir/Cargo.toml"; then
		echo "[metal-policy] error: native UDP no-hxrt fixture emitted hxrt dependency for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/Cargo.toml"
		exit 1
	fi
	if [[ -d "$out_dir/hxrt" ]]; then
		echo "[metal-policy] error: native UDP no-hxrt fixture copied runtime crate for ${failure_label}."
		exit 1
	fi
	if tree_match_regex 'hxrt::|hxrt\.|Dynamic|__rust__|ERaw|SocketHandle|socket_native|sys_net' "$out_dir/src"; then
		echo "[metal-policy] error: native UDP fixture used runtime, Dynamic, raw, or portable sys/socket paths for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/src/main.rs"
		exit 1
	fi
	if ! match_regex 'use std::net::UdpSocket as StdUdpSocket' "$native_udp_rs"; then
		echo "[metal-policy] error: native UDP fixture missing direct std::net UdpSocket import for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'pub struct NativeUdp' "$native_udp_rs" || ! match_regex 'pub struct UdpSocket' "$native_udp_rs"; then
		echo "[metal-policy] error: native UDP fixture missing typed native UDP structs for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'socket: StdUdpSocket' "$native_udp_rs"; then
		echo "[metal-policy] error: native UDP fixture should wrap an owned std::net UDP socket for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'StdUdpSocket::bind\(\("127\.0\.0\.1", port\)\)' "$native_udp_rs"; then
		echo "[metal-policy] error: native UDP fixture missing direct localhost UdpSocket::bind for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn localPort\(&self\) -> Result<i32, String>' "$native_udp_rs" || ! match_regex 'local_addr\(\)' "$native_udp_rs"; then
		echo "[metal-policy] error: native UDP fixture missing localPort/local_addr wiring for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn sendUtf8ToLocalhost\(&self, payload: String, port: i32\) -> Result<i32, String>' "$native_udp_rs"; then
		echo "[metal-policy] error: native UDP fixture missing sendUtf8ToLocalhost helper for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'send_to\(payload\.as_bytes\(\), \("127\.0\.0\.1", port\)\)' "$native_udp_rs"; then
		echo "[metal-policy] error: native UDP fixture missing direct send_to localhost wiring for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn recvUtf8\(&self, max_bytes: i32\) -> Result<String, String>' "$native_udp_rs"; then
		echo "[metal-policy] error: native UDP fixture missing recvUtf8 helper for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'recv_from\(&mut buffer\)' "$native_udp_rs" || ! match_regex 'String::from_utf8\(buffer\)' "$native_udp_rs"; then
		echo "[metal-policy] error: native UDP fixture missing direct recv_from plus UTF-8 decode for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'Result<[^>]*String' "$native_udp_rs"; then
		echo "[metal-policy] error: native UDP fixture should expose Result<_, String> error boundaries for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! (cd "$out_dir" && cargo build -q); then
		echo "[metal-policy] error: native UDP no-hxrt fixture did not cargo-build for ${failure_label}."
		exit 1
	fi
	if ! (cd "$out_dir" && cargo run -q) >"$run_log" 2>&1; then
		echo "[metal-policy] error: native UDP no-hxrt fixture did not cargo-run for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi
	if [[ -s "$run_log" ]]; then
		echo "[metal-policy] error: native UDP fixture produced unexpected stdout/stderr for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi

	rm -f "$log_file" "$run_log"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_socket_error_output_shape_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_socket_error_shape"
	local log_file="$fixture_dir/.compile_socket_error_shape.log"
	local run_log="$fixture_dir/.run_socket_error_shape.log"
	local native_tcp_rs="$out_dir/src/native_tcp_tools.rs"
	local native_udp_rs="$out_dir/src/native_udp_tools.rs"
	local socket_error_rs="$out_dir/src/native_socket_error_tools.rs"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file" "$run_log"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_socket_error_shape) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if [[ ! -f "$socket_error_rs" || ! -f "$native_tcp_rs" || ! -f "$native_udp_rs" ]]; then
		echo "[metal-policy] error: missing socket error/TCP/UDP helper modules for ${failure_label}."
		find "$out_dir/src" -maxdepth 1 -type f -name '*.rs' -print | sed "s|$root_dir|.|g"
		exit 1
	fi
	if match_regex 'hxrt[[:space:]]*=' "$out_dir/Cargo.toml"; then
		echo "[metal-policy] error: socket-error no-hxrt fixture emitted hxrt dependency for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/Cargo.toml"
		exit 1
	fi
	if [[ -d "$out_dir/hxrt" ]]; then
		echo "[metal-policy] error: socket-error no-hxrt fixture copied runtime crate for ${failure_label}."
		exit 1
	fi
	if tree_match_regex 'hxrt::|hxrt\.|Dynamic|__rust__|ERaw|SocketHandle|socket_native|sys_net' "$out_dir/src"; then
		echo "[metal-policy] error: socket-error fixture used runtime, Dynamic, raw, or portable sys/socket paths for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/src/main.rs"
		exit 1
	fi
	if ! match_regex 'pub struct SocketError' "$socket_error_rs" || ! match_regex 'enum SocketErrorKind' "$socket_error_rs"; then
		echo "[metal-policy] error: socket-error fixture missing typed SocketError helper for ${failure_label}."
		sed "s|$root_dir|.|g" "$socket_error_rs"
		exit 1
	fi
	if ! match_regex 'SocketErrorKind::InvalidInput' "$socket_error_rs" || ! match_regex 'SocketErrorKind::Io' "$socket_error_rs" || ! match_regex 'SocketErrorKind::Utf8' "$socket_error_rs"; then
		echo "[metal-policy] error: socket-error fixture missing InvalidInput/Io/Utf8 categories for ${failure_label}."
		sed "s|$root_dir|.|g" "$socket_error_rs"
		exit 1
	fi
	if ! match_regex 'pub\(crate\) fn invalid_input' "$socket_error_rs" || ! match_regex 'pub\(crate\) fn io' "$socket_error_rs" || ! match_regex 'pub\(crate\) fn utf8' "$socket_error_rs"; then
		echo "[metal-policy] error: socket-error fixture missing typed category constructors for ${failure_label}."
		sed "s|$root_dir|.|g" "$socket_error_rs"
		exit 1
	fi
	if ! match_regex 'pub fn isInvalidInput\(&self\) -> bool' "$socket_error_rs" || ! match_regex 'pub fn isIo\(&self\) -> bool' "$socket_error_rs" || ! match_regex 'pub fn isUtf8\(&self\) -> bool' "$socket_error_rs"; then
		echo "[metal-policy] error: socket-error fixture missing predicate accessors for ${failure_label}."
		sed "s|$root_dir|.|g" "$socket_error_rs"
		exit 1
	fi
	if ! match_regex 'use crate::native_socket_error_tools::SocketError' "$native_tcp_rs" || ! match_regex 'use crate::native_socket_error_tools::SocketError' "$native_udp_rs"; then
		echo "[metal-policy] error: TCP/UDP helpers should share native_socket_error_tools::SocketError for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn bindLocalhostDetailed\(port: i32\) -> Result<TcpListener, SocketError>' "$native_tcp_rs" || ! match_regex 'pub fn connectLocalhostDetailed\(port: i32\) -> Result<TcpStream, SocketError>' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP helper missing detailed bind/connect Result<_, SocketError> methods for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn localPortDetailed\(&self\) -> Result<i32, SocketError>' "$native_tcp_rs" || ! match_regex 'pub fn acceptDetailed\(&self\) -> Result<TcpStream, SocketError>' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP listener missing detailed localPort/accept methods for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn writeUtf8AndShutdownWriteDetailed' "$native_tcp_rs" || ! match_regex 'pub fn readToStringDetailed\(&mut self\) -> Result<String, SocketError>' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP stream missing detailed write/read methods for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'port_to_u16_detailed' "$native_tcp_rs" || ! match_regex 'SocketError::invalid_input' "$native_tcp_rs" || ! match_regex 'map_err\(SocketError::io\)' "$native_tcp_rs" || ! match_regex 'map_err\(SocketError::utf8\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP helper should map invalid input, IO, and UTF-8 failures into SocketError for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn bindLocalhostDetailed\(port: i32\) -> Result<UdpSocket, SocketError>' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP helper missing detailed bind Result<_, SocketError> method for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn localPortDetailed\(&self\) -> Result<i32, SocketError>' "$native_udp_rs" || ! match_regex 'pub fn sendUtf8ToLocalhostDetailed' "$native_udp_rs" || ! match_regex 'pub fn recvUtf8Detailed\(&self, max_bytes: i32\) -> Result<String, SocketError>' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP socket missing detailed localPort/send/recv methods for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'positive_len_to_usize_detailed' "$native_udp_rs" || ! match_regex 'SocketError::invalid_input' "$native_udp_rs" || ! match_regex 'map_err\(SocketError::io\)' "$native_udp_rs" || ! match_regex 'map_err\(SocketError::utf8\)' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP helper should map invalid input, IO, and UTF-8 failures into SocketError for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! (cd "$out_dir" && cargo build -q); then
		echo "[metal-policy] error: socket-error no-hxrt fixture did not cargo-build for ${failure_label}."
		exit 1
	fi
	if ! (cd "$out_dir" && cargo run -q) >"$run_log" 2>&1; then
		echo "[metal-policy] error: socket-error no-hxrt fixture did not cargo-run for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi
	if [[ -s "$run_log" ]]; then
		echo "[metal-policy] error: socket-error fixture produced unexpected stdout/stderr for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi

	rm -f "$log_file" "$run_log"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_udp_bytes_output_shape_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_udp_bytes_shape"
	local log_file="$fixture_dir/.compile_udp_bytes_shape.log"
	local run_log="$fixture_dir/.run_udp_bytes_shape.log"
	local native_udp_rs="$out_dir/src/native_udp_tools.rs"
	local socket_error_rs="$out_dir/src/native_socket_error_tools.rs"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file" "$run_log"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_udp_bytes_shape) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if [[ ! -f "$native_udp_rs" || ! -f "$socket_error_rs" ]]; then
		echo "[metal-policy] error: missing UDP byte/socket error helper modules for ${failure_label}."
		find "$out_dir/src" -maxdepth 1 -type f -name '*.rs' -print | sed "s|$root_dir|.|g"
		exit 1
	fi
	if match_regex 'hxrt[[:space:]]*=' "$out_dir/Cargo.toml"; then
		echo "[metal-policy] error: UDP byte no-hxrt fixture emitted hxrt dependency for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/Cargo.toml"
		exit 1
	fi
	if [[ -d "$out_dir/hxrt" ]]; then
		echo "[metal-policy] error: UDP byte no-hxrt fixture copied runtime crate for ${failure_label}."
		exit 1
	fi
	if tree_match_regex 'hxrt::|hxrt\.|Dynamic|__rust__|ERaw|SocketHandle|socket_native|sys_net|haxe_io_bytes' "$out_dir/src"; then
		echo "[metal-policy] error: UDP byte fixture used runtime, Dynamic, raw, portable socket, or haxe.io.Bytes paths for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/src/main.rs"
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn sendBytesToLocalhost\(&self, payload: Vec<i32>, port: i32\) -> Result<i32, String>' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP byte fixture missing String-error byte send method for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn sendBytesToLocalhostDetailed' "$native_udp_rs" || ! match_regex 'payload: Vec<i32>' "$native_udp_rs" || ! match_regex 'Result<i32, SocketError>' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP byte fixture missing detailed byte send method for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn recvBytes\(&self, max_bytes: i32\) -> Result<Vec<i32>, String>' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP byte fixture missing String-error byte receive method for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn recvBytesDetailed\(&self, max_bytes: i32\) -> Result<Vec<i32>, SocketError>' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP byte fixture missing detailed byte receive method for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'fn bytes_to_u8_vec\(payload: Vec<i32>\) -> Result<Vec<u8>, String>' "$native_udp_rs" || ! match_regex 'u8::try_from\(byte\)' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP byte fixture should validate Vec<Int> byte values before u8 conversion for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'bytes_to_u8_vec_detailed\(payload: Vec<i32>\) -> Result<Vec<u8>, SocketError>' "$native_udp_rs" || ! match_regex 'map_err\(SocketError::invalid_input\)' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP byte fixture should map invalid byte values to SocketError::invalid_input for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'fn u8_vec_to_i32_vec\(payload: Vec<u8>\) -> Vec<i32>' "$native_udp_rs" || ! match_regex 'payload\.into_iter\(\)\.map\(i32::from\)\.collect\(\)' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP byte fixture should convert received u8 buffers back to Vec<Int> for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! match_regex 'send_to\(&bytes, \("127\.0\.0\.1", port\)\)' "$native_udp_rs" || ! match_regex 'recv_from\(&mut buffer\)' "$native_udp_rs"; then
		echo "[metal-policy] error: UDP byte fixture missing direct std::net send_to/recv_from wiring for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_udp_rs"
		exit 1
	fi
	if ! (cd "$out_dir" && cargo build -q); then
		echo "[metal-policy] error: UDP byte no-hxrt fixture did not cargo-build for ${failure_label}."
		exit 1
	fi
	if ! (cd "$out_dir" && cargo run -q) >"$run_log" 2>&1; then
		echo "[metal-policy] error: UDP byte no-hxrt fixture did not cargo-run for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi
	if [[ -s "$run_log" ]]; then
		echo "[metal-policy] error: UDP byte fixture produced unexpected stdout/stderr for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi

	rm -f "$log_file" "$run_log"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_tcp_bytes_output_shape_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_tcp_bytes_shape"
	local log_file="$fixture_dir/.compile_tcp_bytes_shape.log"
	local run_log="$fixture_dir/.run_tcp_bytes_shape.log"
	local native_tcp_rs="$out_dir/src/native_tcp_tools.rs"
	local socket_error_rs="$out_dir/src/native_socket_error_tools.rs"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file" "$run_log"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_tcp_bytes_shape) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if [[ ! -f "$native_tcp_rs" || ! -f "$socket_error_rs" ]]; then
		echo "[metal-policy] error: missing TCP byte/socket error helper modules for ${failure_label}."
		find "$out_dir/src" -maxdepth 1 -type f -name '*.rs' -print | sed "s|$root_dir|.|g"
		exit 1
	fi
	if match_regex 'hxrt[[:space:]]*=' "$out_dir/Cargo.toml"; then
		echo "[metal-policy] error: TCP byte no-hxrt fixture emitted hxrt dependency for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/Cargo.toml"
		exit 1
	fi
	if [[ -d "$out_dir/hxrt" ]]; then
		echo "[metal-policy] error: TCP byte no-hxrt fixture copied runtime crate for ${failure_label}."
		exit 1
	fi
	if tree_match_regex 'hxrt::|hxrt\.|Dynamic|__rust__|ERaw|SocketHandle|socket_native|sys_net|haxe_io_bytes' "$out_dir/src"; then
		echo "[metal-policy] error: TCP byte fixture used runtime, Dynamic, raw, portable socket, or haxe.io.Bytes paths for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/src/main.rs"
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn writeBytesAndShutdownWrite\(&mut self, payload: Vec<i32>\) -> Result<bool, String>' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP byte fixture missing String-error byte write method for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn writeBytesAndShutdownWriteDetailed' "$native_tcp_rs" || ! match_regex 'payload: Vec<i32>' "$native_tcp_rs" || ! match_regex 'Result<bool, SocketError>' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP byte fixture missing detailed byte write method for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn readBytes\(&mut self\) -> Result<Vec<i32>, String>' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP byte fixture missing String-error byte read method for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'pub fn readBytesDetailed\(&mut self\) -> Result<Vec<i32>, SocketError>' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP byte fixture missing detailed byte read method for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'fn bytes_to_u8_vec\(payload: Vec<i32>\) -> Result<Vec<u8>, String>' "$native_tcp_rs" || ! match_regex 'u8::try_from\(byte\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP byte fixture should validate Vec<Int> byte values before u8 conversion for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'bytes_to_u8_vec_detailed\(payload: Vec<i32>\) -> Result<Vec<u8>, SocketError>' "$native_tcp_rs" || ! match_regex 'map_err\(SocketError::invalid_input\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP byte fixture should map invalid byte values to SocketError::invalid_input for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'fn u8_vec_to_i32_vec\(payload: Vec<u8>\) -> Vec<i32>' "$native_tcp_rs" || ! match_regex 'payload\.into_iter\(\)\.map\(i32::from\)\.collect\(\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP byte fixture should convert received u8 buffers back to Vec<Int> for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! match_regex 'write_all\(&bytes\)' "$native_tcp_rs" || ! match_regex 'shutdown\(Shutdown::Write\)' "$native_tcp_rs" || ! match_regex 'read_to_end\(&mut output\)' "$native_tcp_rs"; then
		echo "[metal-policy] error: TCP byte fixture missing direct write_all, Shutdown::Write, or read_to_end wiring for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_tcp_rs"
		exit 1
	fi
	if ! (cd "$out_dir" && cargo build -q); then
		echo "[metal-policy] error: TCP byte no-hxrt fixture did not cargo-build for ${failure_label}."
		exit 1
	fi
	if ! (cd "$out_dir" && cargo run -q) >"$run_log" 2>&1; then
		echo "[metal-policy] error: TCP byte no-hxrt fixture did not cargo-run for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi
	if [[ -s "$run_log" ]]; then
		echo "[metal-policy] error: TCP byte fixture produced unexpected stdout/stderr for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi

	rm -f "$log_file" "$run_log"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_native_process_output_shape_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local case_start="$SECONDS"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_native_process_shape"
	local log_file="$fixture_dir/.compile_native_process_shape.log"
	local run_log="$fixture_dir/.run_native_process_shape.log"
	local native_process_rs="$out_dir/src/native_process_tools.rs"
	echo "[metal-policy] case: ${failure_label}"

	rm -rf "$out_dir"
	rm -f "$log_file" "$run_log"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_output=out_native_process_shape) >"$log_file" 2>&1
	local status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label}."
		sed "s|$root_dir|.|g" "$log_file"
		exit 1
	fi

	if [[ ! -f "$native_process_rs" ]]; then
		echo "[metal-policy] error: missing native_process_tools.rs for ${failure_label}."
		exit 1
	fi
	if match_regex 'hxrt[[:space:]]*=' "$out_dir/Cargo.toml"; then
		echo "[metal-policy] error: native process no-hxrt fixture emitted hxrt dependency for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/Cargo.toml"
		exit 1
	fi
	if [[ -d "$out_dir/hxrt" ]]; then
		echo "[metal-policy] error: native process no-hxrt fixture copied runtime crate for ${failure_label}."
		exit 1
	fi
	if tree_match_regex 'hxrt::|hxrt\.|Dynamic|__rust__|ERaw|ProcessHandle|hxrt::process|sys_io_' "$out_dir/src"; then
		echo "[metal-policy] error: native process fixture used runtime, Dynamic, raw, or portable sys/process paths for ${failure_label}."
		sed "s|$root_dir|.|g" "$out_dir/src/main.rs"
		exit 1
	fi
	if ! match_regex 'std::process::Command::new' "$native_process_rs"; then
		echo "[metal-policy] error: native process fixture missing direct std::process::Command helper for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_process_rs"
		exit 1
	fi
	if ! match_regex 'std::process::Stdio::null' "$native_process_rs"; then
		echo "[metal-policy] error: native process status helper should suppress inherited stdout/stderr for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_process_rs"
		exit 1
	fi
	if ! match_regex '\.status\(\)' "$native_process_rs"; then
		echo "[metal-policy] error: native process fixture missing status execution for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_process_rs"
		exit 1
	fi
	if ! match_regex '\.output\(\)' "$native_process_rs"; then
		echo "[metal-policy] error: native process fixture missing owned output capture for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_process_rs"
		exit 1
	fi
	if ! match_regex 'String::from_utf8' "$native_process_rs"; then
		echo "[metal-policy] error: native process fixture missing explicit UTF-8 stdout boundary for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_process_rs"
		exit 1
	fi
	if ! match_regex 'Result<[^>]*String' "$native_process_rs"; then
		echo "[metal-policy] error: native process fixture should expose Result<_, String> error boundaries for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_process_rs"
		exit 1
	fi
	if ! match_regex '&Vec<String>' "$native_process_rs"; then
		echo "[metal-policy] error: native process fixture should use rust.Vec/String args, not Haxe Array, for ${failure_label}."
		sed "s|$root_dir|.|g" "$native_process_rs"
		exit 1
	fi
	if [[ "$fixture_rel" == *"metal_no_hxrt_command_output"* ]]; then
		if ! match_regex 'pub struct CommandOutput' "$native_process_rs"; then
			echo "[metal-policy] error: command-output fixture missing typed CommandOutput helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'std::process::Output' "$native_process_rs"; then
			echo "[metal-policy] error: command-output fixture should convert owned std::process::Output for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'outputUtf8' "$native_process_rs"; then
			echo "[metal-policy] error: command-output fixture missing NativeCommands.outputUtf8 helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'stderrUtf8' "$native_process_rs"; then
			echo "[metal-policy] error: command-output fixture missing stderr UTF-8 accessor for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'stdout: Vec<u8>' "$native_process_rs" || ! match_regex 'stderr: Vec<u8>' "$native_process_rs"; then
			echo "[metal-policy] error: command-output fixture should store owned stdout/stderr bytes for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'Result<CommandOutput, String>' "$native_process_rs"; then
			echo "[metal-policy] error: command-output fixture should expose Result<CommandOutput, String> for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
	fi
	if [[ "$fixture_rel" == *"metal_no_hxrt_command_cwd"* ]]; then
		if ! match_regex 'current_dir\(cwd\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-cwd fixture missing direct Command::current_dir(cwd) for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'statusCodeInDir' "$native_process_rs"; then
			echo "[metal-policy] error: command-cwd fixture missing statusCodeInDir helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'outputUtf8InDir' "$native_process_rs"; then
			echo "[metal-policy] error: command-cwd fixture missing outputUtf8InDir helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'cwd: &std::path::PathBuf' "$native_process_rs"; then
			echo "[metal-policy] error: command-cwd fixture should pass cwd as borrowed PathBuf for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
	fi
	if [[ "$fixture_rel" == *"metal_no_hxrt_command_env"* || "$fixture_rel" == *"metal_no_hxrt_command_cwd_env"* || "$fixture_rel" == *"metal_no_hxrt_command_stdin_cwd_env"* || "$fixture_rel" == *"metal_no_hxrt_command_spec"* ]]; then
		if ! match_regex 'pub struct CommandEnv' "$native_process_rs"; then
			echo "[metal-policy] error: command-env fixture missing typed CommandEnv helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'ops: Vec<CommandEnvOp>' "$native_process_rs"; then
			echo "[metal-policy] error: command-env fixture should store typed ordered env operations for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'enum CommandEnvOp' "$native_process_rs" || ! match_regex 'CommandEnvOp::Set' "$native_process_rs"; then
			echo "[metal-policy] error: command-env fixture should model set operations with a typed CommandEnvOp enum for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'command\.env\(key\.as_str\(\), value\.as_str\(\)\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-env fixture missing direct Command::env wiring for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'env: &CommandEnv' "$native_process_rs"; then
			echo "[metal-policy] error: command-env fixture should pass env overrides by borrowed CommandEnv for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'statusCodeWithEnv' "$native_process_rs"; then
			echo "[metal-policy] error: command-env fixture missing statusCodeWithEnv helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'outputUtf8WithEnv' "$native_process_rs"; then
			echo "[metal-policy] error: command-env fixture missing outputUtf8WithEnv helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
	fi
	if [[ "$fixture_rel" == *"metal_no_hxrt_command_cwd_env"* || "$fixture_rel" == *"metal_no_hxrt_command_stdin_cwd_env"* ]]; then
		if ! match_regex 'fn command_in_dir_with_env' "$native_process_rs"; then
			echo "[metal-policy] error: command-cwd-env fixture missing composed command_in_dir_with_env helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'command_in_dir\(program, args, cwd\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-cwd-env fixture should reuse command_in_dir for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'apply_env\(&mut command, env\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-cwd-env fixture should apply CommandEnv to the current_dir command for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'statusCodeInDirWithEnv' "$native_process_rs"; then
			echo "[metal-policy] error: command-cwd-env fixture missing statusCodeInDirWithEnv helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'outputUtf8InDirWithEnv' "$native_process_rs"; then
			echo "[metal-policy] error: command-cwd-env fixture missing outputUtf8InDirWithEnv helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
	fi
	if [[ "$fixture_rel" == *"metal_no_hxrt_command_env_ops"* ]]; then
		if ! match_regex 'CommandEnvOp::Remove' "$native_process_rs" || ! match_regex 'CommandEnvOp::Clear' "$native_process_rs"; then
			echo "[metal-policy] error: command-env-ops fixture should model remove/clear as typed CommandEnvOp variants for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'command\.env_remove\(key\.as_str\(\)\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-env-ops fixture missing direct Command::env_remove wiring for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'command\.env_clear\(\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-env-ops fixture missing direct Command::env_clear wiring for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'pub fn remove\(&mut self, key: String\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-env-ops fixture missing CommandEnv.remove helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'pub fn clear\(&mut self\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-env-ops fixture missing CommandEnv.clear helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
	fi
	if [[ "$fixture_rel" == *"metal_no_hxrt_command_stdin"* ]]; then
		if ! match_regex 'fn write_child_stdin' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin fixture missing child stdin writer helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'stdin\(std::process::Stdio::piped\(\)\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin fixture missing direct Stdio::piped stdin wiring for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'stdout\(std::process::Stdio::null\(\)\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin status helper should silence stdout for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'stdout\(std::process::Stdio::piped\(\)\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin output helper should pipe stdout for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'write_all\(stdin_utf8\.as_bytes\(\)\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin fixture missing direct UTF-8 stdin write for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'wait_with_output\(\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin output helper should wait_with_output for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'statusCodeWithStdin' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin fixture missing statusCodeWithStdin helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'outputUtf8WithStdin' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin fixture missing outputUtf8WithStdin helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'stdin_utf8: String' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin fixture should pass stdin input as owned String for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
	fi
	if [[ "$fixture_rel" == *"metal_no_hxrt_command_stdin_cwd_env"* ]]; then
		if ! match_regex 'statusCodeInDirWithEnvAndStdin' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin-cwd-env fixture missing statusCodeInDirWithEnvAndStdin helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'outputUtf8InDirWithEnvAndStdin' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin-cwd-env fixture missing outputUtf8InDirWithEnvAndStdin helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'status_code_with_stdin\(' "$native_process_rs" || ! match_regex 'command_in_dir_with_env\(program, args, cwd, env\)' "$native_process_rs" || ! match_regex 'stdin_utf8\.as_str\(\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin-cwd-env status helper should compose command_in_dir_with_env with stdin writing for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'output_with_stdin\(' "$native_process_rs" || ! match_regex 'command_in_dir_with_env\(program, args, cwd, env\)' "$native_process_rs" || ! match_regex 'stdin_utf8\.as_str\(\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-stdin-cwd-env output helper should compose command_in_dir_with_env with stdin output capture for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
	fi
	if [[ "$fixture_rel" == *"metal_no_hxrt_command_spec"* ]]; then
		if ! match_regex 'pub struct CommandSpec' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture missing typed CommandSpec helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'program: std::path::PathBuf' "$native_process_rs" || ! match_regex 'args: Vec<String>' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture should store owned program and args for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'cwd: Option<std::path::PathBuf>' "$native_process_rs" || ! match_regex 'env: Option<CommandEnv>' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture should store optional cwd and CommandEnv for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'stdin_utf8: Option<String>' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture should store optional owned stdin input for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'pub fn new\(program: &std::path::PathBuf, args: &Vec<String>\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture missing borrowed constructor inputs for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'pub fn inDir\(&mut self, cwd: &std::path::PathBuf\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture missing inDir mutator for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'pub fn withEnv\(&mut self, env: &CommandEnv\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture missing withEnv mutator for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'pub fn withStdin\(&mut self, stdin_utf8: String\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture missing withStdin mutator for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'fn command_from_spec' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture missing command_from_spec builder for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'command\(&spec\.program, &spec\.args\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture should build from stored program and args for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'if let Some\(cwd\) = &spec\.cwd' "$native_process_rs" || ! match_regex 'command\.current_dir\(cwd\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture should apply optional cwd directly for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'if let Some\(env\) = &spec\.env' "$native_process_rs" || ! match_regex 'apply_env\(&mut command, env\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture should apply optional CommandEnv directly for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'statusCodeFromSpec' "$native_process_rs" || ! match_regex 'outputUtf8FromSpec' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec fixture missing NativeCommands spec execution helpers for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'status_code_with_stdin\(command, stdin_utf8\.as_str\(\)\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec status helper should compose spec builder with borrowed stdin writing for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'output_with_stdin\(command, stdin_utf8\.as_str\(\)\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-spec output helper should compose spec builder with borrowed stdin output capture for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
	fi
	if [[ "$fixture_rel" == *"metal_no_hxrt_command_error"* ]]; then
		if ! match_regex 'pub struct CommandError' "$native_process_rs"; then
			echo "[metal-policy] error: command-error fixture missing typed CommandError helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'enum CommandErrorKind' "$native_process_rs" || ! match_regex 'CommandErrorKind::Io' "$native_process_rs" || ! match_regex 'CommandErrorKind::Utf8' "$native_process_rs" || ! match_regex 'CommandErrorKind::Stdin' "$native_process_rs"; then
			echo "[metal-policy] error: command-error fixture should model typed IO/UTF-8/stdin categories for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'pub fn message\(&self\) -> String' "$native_process_rs" || ! match_regex 'pub fn isIo\(&self\) -> bool' "$native_process_rs" || ! match_regex 'pub fn isUtf8\(&self\) -> bool' "$native_process_rs" || ! match_regex 'pub fn isStdin\(&self\) -> bool' "$native_process_rs"; then
			echo "[metal-policy] error: command-error fixture missing typed error accessors for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'map_err\(CommandError::io\)' "$native_process_rs" || ! match_regex 'map_err\(CommandError::utf8\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-error fixture should map std::io and FromUtf8Error into CommandError for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'statusCodeDetailedFromSpec' "$native_process_rs" || ! match_regex 'outputUtf8DetailedFromSpec' "$native_process_rs"; then
			echo "[metal-policy] error: command-error fixture missing detailed NativeCommands spec helpers for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'stdoutUtf8Detailed' "$native_process_rs" || ! match_regex 'stderrUtf8Detailed' "$native_process_rs"; then
			echo "[metal-policy] error: command-error fixture missing detailed CommandOutput UTF-8 helpers for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'Result<i32, CommandError>' "$native_process_rs" || ! match_regex 'Result<CommandOutput, CommandError>' "$native_process_rs" || ! match_regex 'Result<String, CommandError>' "$native_process_rs"; then
			echo "[metal-policy] error: command-error fixture should expose typed Result boundaries for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
	fi
	if [[ "$fixture_rel" == *"metal_no_hxrt_command_child"* ]]; then
		if ! match_regex 'pub struct CommandChild' "$native_process_rs" || ! match_regex 'child: std::process::Child' "$native_process_rs"; then
			echo "[metal-policy] error: command-child fixture missing typed std::process::Child owner for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'pub fn writeStdinAndClose\(&mut self, stdin_utf8: String\) -> Result<bool, CommandError>' "$native_process_rs"; then
			echo "[metal-policy] error: command-child fixture missing write-and-close stdin lifecycle helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'pub fn wait\(&mut self\) -> Result<i32, CommandError>' "$native_process_rs" || ! match_regex 'pub fn killAndWait\(&mut self\) -> Result<i32, CommandError>' "$native_process_rs"; then
			echo "[metal-policy] error: command-child fixture missing wait and kill/wait lifecycle helpers for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'CommandErrorKind::Lifecycle' "$native_process_rs" || ! match_regex 'pub fn isLifecycle\(&self\) -> bool' "$native_process_rs"; then
			echo "[metal-policy] error: command-child fixture should expose typed lifecycle errors for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'pub fn spawnChildFromSpec\(spec: &CommandSpec\) -> Result<CommandChild, CommandError>' "$native_process_rs"; then
			echo "[metal-policy] error: command-child fixture missing NativeCommands spawnChildFromSpec helper for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'spec\.stdin_utf8\.is_some\(\)' "$native_process_rs" || ! match_regex 'spawnChildFromSpec requires stdin to be written through CommandChild' "$native_process_rs"; then
			echo "[metal-policy] error: command-child fixture should reject one-shot stdin specs at live-spawn boundary for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex 'stdin\(std::process::Stdio::piped\(\)\)' "$native_process_rs" || ! match_regex 'stdout\(std::process::Stdio::null\(\)\)' "$native_process_rs" || ! match_regex 'stderr\(std::process::Stdio::null\(\)\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-child fixture should spawn with piped stdin and null output streams for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
		if ! match_regex '\.spawn\(\)' "$native_process_rs" || ! match_regex 'map\(\|child\| CommandChild \{ child \}\)' "$native_process_rs"; then
			echo "[metal-policy] error: command-child fixture should wrap direct std::process spawn output in CommandChild for ${failure_label}."
			sed "s|$root_dir|.|g" "$native_process_rs"
			exit 1
		fi
	fi
	if ! (cd "$out_dir" && cargo build -q); then
		echo "[metal-policy] error: native process no-hxrt fixture did not cargo-build for ${failure_label}."
		exit 1
	fi
	if ! (cd "$out_dir" && cargo run -q) >"$run_log" 2>&1; then
		echo "[metal-policy] error: native process no-hxrt fixture did not cargo-run for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi
	if [[ -s "$run_log" ]]; then
		echo "[metal-policy] error: native process status helper leaked child output for ${failure_label}."
		sed "s|$root_dir|.|g" "$run_log"
		exit 1
	fi

	rm -f "$log_file" "$run_log"
	rm -rf "$out_dir"
	finish_policy_case "$failure_label" "$case_start"
}

run_negative_case "test/negative/metal_raw_rust" 'Strict mode forbids `__rust__\(\)` code injection in application code' \
	'raw __rust__ in app code under metal profile'
run_negative_case "test/negative/metal_raw_rust_under_std" 'Strict mode forbids `__rust__\(\)` code injection in application code' \
	'raw __rust__ in user code under a /std/ path must still be rejected'
run_negative_case "test/negative/metal_fs_raw_escape" 'Strict mode forbids `__rust__\(\)` code injection in application code' \
	'raw std::fs escape in app code must use typed rust.fs facade'
run_negative_case "test/negative/metal_process_raw_escape" 'Strict mode forbids `__rust__\(\)` code injection in application code' \
	'raw std::process escape in app code must use typed rust.process facade'
run_negative_case "test/negative/metal_stringly_dsl_app_api" '`rust\.metal\.Code\.expr` is a controlled raw Rust escape hatch' \
	'stringly rust.metal.Code app API requires scoped raw authority'
run_negative_case "test/negative/metal_reflect" 'metal profile forbids reflection/runtime-introspection modules' \
	'Reflect usage under metal profile' \
	'^Main\.hx:[0-9]+: lines [0-9]+-[0-9]+ : Rust profile contract violation\(s\):'
run_negative_case "test/negative/metal_type_reflection" 'metal profile forbids reflection/runtime-introspection modules' \
	'Type runtime introspection under metal profile'
run_negative_case "test/negative/metal_dynamic_access" 'metal profile forbids haxe\.DynamicAccess runtime map semantics' \
	'haxe.DynamicAccess usage under metal profile' \
	'^Main\.hx:[0-9]+: lines [0-9]+-[0-9]+ : Rust profile contract violation\(s\):'
run_negative_case "test/negative/metal_island_dynamic_access" 'Metal island violation in module `Main`.*dynamic_boundary/dynamic_access' \
	'@:haxeMetal module rejects dynamic boundary usage in portable profile'
run_negative_case "test/negative/metal_island_raw_fallback" 'Metal island violation in module `Main`.*raw Rust expression node\(s\) \(`ERaw`\)' \
	'@:haxeMetal module rejects raw fallback codegen in portable profile'
run_negative_case "test/negative/metal_island_allow_raw_fallback" 'Metal island violation in module `Main`.*raw Rust expression node\(s\) \(`ERaw`\)' \
	'@:rustAllowRaw does not bypass @:haxeMetal raw-fallback restrictions'
run_negative_case "test/negative/metal_dsl_bypasses_policy" 'Metal island violation in module `Main`.*raw Rust expression node\(s\) \(`ERaw`\)' \
	'rust.metal.Code does not bypass @:haxeMetal raw-fallback restrictions'
run_negative_case "test/negative/metal_island_rust_alias_dynamic_access" 'Metal island violation in module `Main`.*dynamic_boundary/dynamic_access' \
	'@:rustMetal alias still enforces metal island contract in portable profile'
run_negative_case "test/negative/metal_nullable_strings" 'metal profile does not allow -D rust_string_nullable in metal-clean mode' \
	'rust_string_nullable under metal profile' \
	'^Main\.hx:[0-9]+: lines [0-9]+-[0-9]+ : Rust profile contract violation\(s\):'
run_negative_case "test/negative/metal_string_null_forbidden" 'metal non-null string contract forbids `null` for `String`' \
	'metal non-null contract rejects String = null assignments'
run_negative_case "test/negative/metal_no_hxrt_requires_metal" '`-D rust_no_hxrt` currently requires `-D reflaxe_rust_profile=metal`\.' \
	'rust_no_hxrt requires metal profile'
run_negative_case "test/negative/metal_no_hxrt_dynamic_boundary" 'reasonKind `dynamic`.*typed_ast `Main`' \
	'rust_no_hxrt semantic eligibility rejects Dynamic before emitted-code guard'
run_negative_case "test/negative/metal_no_hxrt_dynamic_boundary" 'reasonKind `anonymous_object`.*typed_ast `Main`' \
	'rust_no_hxrt semantic eligibility rejects anonymous runtime objects before emitted-code guard'
run_negative_case "test/negative/metal_no_hxrt_reflection_boundary" 'reasonKind `reflection`.*typed_ast `Main`' \
	'rust_no_hxrt semantic eligibility rejects reflection before emitted-code guard'
run_negative_case "test/negative/metal_no_hxrt_platform_boundary" 'reasonKind `platform_abstraction`.*typed_ast `Main`' \
	'rust_no_hxrt semantic eligibility rejects platform runtime abstractions'
run_negative_case "test/negative/metal_no_hxrt_runtime_boundary" '`-D rust_no_hxrt` violation in module' \
	'rust_no_hxrt rejects runtime-dependent output'
run_negative_case "test/negative/async_preview_removed" '`-D rust_async_preview` was removed\. Use `-D rust_async`\.' \
	'rust_async_preview define removed'
run_negative_case "test/negative/async_main_boundary" '`main` must stay synchronous for the Rust async contract\.' \
	'async boundary keeps main synchronous'
run_negative_case "test/negative/async_constructor_contract" 'Constructors cannot be marked `@:async` / `@:rustAsync` under the Rust async contract\.' \
	'async contract rejects constructors'
run_negative_case "test/negative/profile_removed_idiomatic" 'Unknown `-D reflaxe_rust_profile=idiomatic`\. Expected portable\|metal\.' \
	'idiomatic profile selector removed'
run_negative_case "test/negative/profile_removed_rusty" 'Unknown `-D reflaxe_rust_profile=rusty`\. Expected portable\|metal\.' \
	'rusty profile selector removed'
run_negative_case "test/negative/portable_native_import_strict" 'portable contract imported native target modules: rust\.Option' \
	'portable native-target import strict mode rejects rust.* imports' \
	'^Main\.hx:[0-9]+: lines [0-9]+-[0-9]+ : Rust profile contract violation\(s\):'
run_negative_case "test/negative/portable_native_typed_strict" 'portable contract imported native target modules: rust\.Option' \
	'portable native-target strict mode rejects fully qualified typed rust.* usage' \
	'^Main\.hx:[0-9]+: lines [0-9]+-[0-9]+ : Rust profile contract violation\(s\):'
run_negative_case "test/negative/send_sync_borrow_capture" 'Rust concurrency contract violation: sys\.thread\.Thread\.create\(job\) captures `borrowed` with borrowed type `rust\.Ref<T>`' \
	'spawn closure captures borrow-only value under rust_send_sync_strict'
run_negative_case "test/negative/send_sync_str_capture" 'Rust concurrency contract violation: sys\.thread\.Thread\.create\(job\) captures `borrowed` with borrowed type `rust\.Str`' \
	'spawn closure captures borrowed Str under rust_send_sync_strict'
run_negative_case "test/negative/metal_ref_escape" 'Rust borrow region violation: rust\.Borrow\.withRef creates rust\.Ref<T> `borrowed` that must not escape its callback region\.' \
	'metal borrow region rejects escaped rust.Ref token' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_return_escape" 'Rust borrow region violation: rust\.Borrow\.withRef creates rust\.Ref<T> `borrowed` that must not escape its callback region\.' \
	'metal borrow region rejects returned rust.Ref token' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_assignment_escape" 'Rust borrow region violation: rust\.Borrow\.withRef creates rust\.Ref<T> `borrowed` that must not escape its callback region\.' \
	'metal borrow region rejects assigned rust.Ref token' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_literal_escape" 'Rust borrow region violation: rust\.Borrow\.withRef creates rust\.Ref<T> `borrowed` that must not escape its callback region\.' \
	'metal borrow region rejects literal-contained rust.Ref token' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_closure_escape" 'Rust borrow region violation: rust\.Borrow\.withRef creates rust\.Ref<T> `borrowed` that must not escape its callback region\.' \
	'metal borrow region rejects closure-captured rust.Ref token' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_alias_tail_escape" 'Rust borrow region violation: returned borrow-only alias `alias` \(rust\.Ref<T>\)\. Return an owned value derived from the borrow instead\.' \
	'typed borrow region rejects tail-returned rust.Ref alias' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_alias_return_escape" 'Rust borrow region violation: returned borrow-only alias `alias` \(rust\.Ref<T>\)\. Return an owned value derived from the borrow instead\.' \
	'typed borrow region rejects explicitly returned rust.Ref alias' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_alias_field_storage_escape" 'Rust borrow region violation: stored borrow-only alias `alias` \(rust\.Ref<T>\) in a field/static slot\.' \
	'typed borrow region rejects rust.Ref alias field/static storage' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_alias_closure_storage_escape" 'Rust borrow region violation: stored closure captures borrow-only alias `alias` \(rust\.Ref<T>\)\.' \
	'typed borrow region rejects stored closure capture of rust.Ref alias' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_option_wrapper_escape" 'Rust borrow region violation: returned value packages borrow-only alias `alias` \(rust\.Ref<T>\)\. Return an owned value derived from the borrow instead of wrapping the borrow token\.' \
	'typed borrow region rejects Option-wrapped rust.Ref alias' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_object_wrapper_escape" 'Rust borrow region violation: returned value packages borrow-only alias `alias` \(rust\.Ref<T>\)\. Return an owned value derived from the borrow instead of wrapping the borrow token\.' \
	'typed borrow region rejects object-wrapped rust.Ref alias' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_helper_wrapper_escape" 'Rust borrow region violation: returned value packages borrow-only alias `alias` \(rust\.Ref<T>\)\. Return an owned value derived from the borrow instead of wrapping the borrow token\.' \
	'typed borrow region rejects helper-wrapped rust.Ref alias' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_ref_throw_escape" 'Rust borrow region violation: thrown borrow-only alias `alias` \(rust\.Ref<T>\)\. Throw owned error data instead of a scoped borrow token\.' \
	'typed borrow region rejects thrown rust.Ref alias' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_raii_guard_escape" 'Rust borrow region violation: returned borrow-only alias `guard` \(rust\.Ref<T>\)\. Return an owned value derived from the borrow instead\.' \
	'typed borrow region rejects escaped scoped RAII guard token' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_mut_ref_escape" 'Rust borrow region violation: rust\.Borrow\.withMut creates rust\.MutRef<T> `borrowed` that must not escape its callback region\.' \
	'metal borrow region rejects escaped rust.MutRef token' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_mut_ref_nested_overlap" 'Rust borrow region violation: overlapping mutable borrow of `map` through `second` \(rust\.MutRef<T>\) while `first` is still active\.' \
	'typed borrow region rejects nested overlapping rust.MutRef regions' \
	'^Main\.hx:[0-9]+: lines [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_slice_escape" 'Rust borrow region violation: rust\.SliceTools\.with creates rust\.Slice<T> `slice` that must not escape its callback region\.' \
	'metal borrow region rejects escaped rust.Slice token' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_slice_alias_return_escape" 'Rust borrow region violation: returned borrow-only alias `alias` \(rust\.Slice<T>\)\. Return an owned value derived from the borrow instead\.' \
	'typed borrow region rejects returned rust.Slice alias' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_mut_slice_escape" 'Rust borrow region violation: rust\.MutSliceTools\.with creates rust\.MutSlice<T> `slice` that must not escape its callback region\.' \
	'metal borrow region rejects escaped rust.MutSlice token' \
	'^Main\.hx:[0-9]+: characters [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_mut_slice_nested_overlap" 'Rust borrow region violation: overlapping mutable borrow of `values` through `second` \(rust\.MutSlice<T>\) while `first` is still active\.' \
	'typed borrow region rejects nested overlapping rust.MutSlice regions' \
	'^Main\.hx:[0-9]+: lines [0-9]+-[0-9]+ : Rust borrow region violation:'
run_negative_case "test/negative/metal_mut_region_sibling_overlap" 'Rust borrow region violation: overlapping mutable borrow of `values` through `slice` \(rust\.MutSlice<T>\) while `outer` is still active\.' \
	'typed borrow region rejects sibling mutable helper under active mutable borrow' \
	'^Main\.hx:[0-9]+: lines [0-9]+-[0-9]+ : Rust borrow region violation:'
run_warning_case "test/negative/metal_dynamic_access" "compile.fallback.hxml" 'Rust profile contract: metal profile forbids haxe\.DynamicAccess runtime map semantics' \
	'1' 'haxe.DynamicAccess warning in explicit metal fallback mode'
run_warning_case "test/snapshot/metal_typed_injection" "compile.hxml" 'metal raw expr \[Main\]' \
	'2' 'metal raw debug warnings include source location' \
	'^Main\.hx:[0-9]+: lines [0-9]+-[0-9]+ : Warning : metal raw expr \[Main\]' \
	'rust_debug_metal_raw'
run_warning_case "test/negative/portable_native_import_strict" "compile.warn.hxml" 'Rust profile contract: portable contract imported native target modules: rust\.Option' \
	'1' 'portable profile warns when app code imports target-specific module surface'
run_warning_case "test/negative/metal_dynamic_access" "compile.viability.hxml" 'Metal viability: overall score [0-9]+/100, modules=[0-9]+, ready=[0-9]+, blockers=[0-9]+\.' \
	'1' 'metal viability summary warning output'
run_report_case "test/negative/metal_dynamic_access" "compile.viability.hxml" \
	'metal viability deterministic report artifacts'
run_contract_report_case "examples/hello" "compile.hxml" "portable" \
	'portable contract report artifacts' \
	'false' 'true' 'false' 'false' 'false' 'false' 'true'
run_contract_report_case "examples/profile_storyboard" "compile.metal.hxml" "metal" \
	'metal contract report artifacts (profile_storyboard)' \
	'true' 'true' 'true' 'false' 'false' 'false' 'false'
run_contract_report_case "test/positive/metal_no_hxrt_minimal" "compile.hxml" "metal" \
	'metal no-hxrt contract report artifacts' \
	'true' 'false' 'false' 'true' 'true' 'false' 'false'
run_contract_report_case "test/snapshot/reflaxe_std_option_result" "compile.hxml" "portable" \
	'portable facade contract report records Option/Result surfaces' \
	'false' 'true' 'false' 'false' 'false' 'false' 'true' \
	$'"surfaceId":[[:space:]]*"reflaxe\\.std\\.Option"\n"surfaceId":[[:space:]]*"reflaxe\\.std\\.Result"\n"rustRepresentation":[[:space:]]*"core::option::Option<T>"\n"rustRepresentation":[[:space:]]*"core::result::Result<T,E>"\n"reason":[[:space:]]*"admitted_portable_facade"' \
	$'`reflaxe\\.std\\.Option` \\(`portable_facade` -> `core::option::Option<T>`\n`reflaxe\\.std\\.Result` \\(`portable_facade` -> `core::result::Result<T,E>`\n`reflaxe\\.std\\.Option` -> `core::option::Option<T>` \\(`admitted_portable_facade`\\)\n`reflaxe\\.std\\.Result` -> `core::result::Result<T,E>` \\(`admitted_portable_facade`\\)'
run_contract_report_case "test/snapshot/portable_facade_contract_report" "compile.hxml" "portable" \
	'portable facade contract-report fixture records admitted surfaces without native imports' \
	'false' 'true' 'false' 'false' 'false' 'false' 'true' \
	$'"portableNativeImportsDetected":[[:space:]]*false\n"nativeImportHitsTyped":[[:space:]]*\\[\n"surfaceId":[[:space:]]*"reflaxe\\.std\\.Option"\n"surfaceId":[[:space:]]*"reflaxe\\.std\\.Result"\n"requiresRustImport":[[:space:]]*false\n"rustRepresentation":[[:space:]]*"core::option::Option<T>"\n"rustRepresentation":[[:space:]]*"core::result::Result<T,E>"\n"reason":[[:space:]]*"admitted_portable_facade"' \
	$'## Native Import Hits\n- none\n## Typed Native Import Hits\n- none\n`reflaxe\\.std\\.Option` \\(`portable_facade` -> `core::option::Option<T>`\n`reflaxe\\.std\\.Result` \\(`portable_facade` -> `core::result::Result<T,E>`'
run_contract_report_case "test/positive/portable_native_typed_report" "compile.hxml" "portable" \
	'portable contract report records fully qualified rust.* typed usage' \
	'false' 'true' 'false' 'false' 'false' 'false' 'true' \
	$'"portableNativeImportsDetected":[[:space:]]*true\n"nativeImportHitsTyped":[[:space:]]*\\[\n"modulePath":[[:space:]]*"rust\\.Option"\n"nativeFamily":[[:space:]]*"rust"\n"surfaceKind":[[:space:]]*"rust_native"\n"sourceKind":[[:space:]]*"typed_module_usage"' \
	$'## Native Import Hits\n- none\n## Typed Native Import Hits\n- `rust\\.Option` \\(`rust_native`, family: `rust`, source: `typed_module_usage`\\)'
run_portable_facade_output_shape_case "test/snapshot/portable_facade_native_option_result" "compile.hxml" \
	'portable facade Option/Result output uses native Rust shapes'
run_runtime_plan_report_case "examples/hello" "compile.hxml" "portable" "selective" \
	'portable runtime plan artifacts' \
	"" \
	"" \
	"" \
	'"reasonKind":[[:space:]]*"haxe_string_semantics"' \
	'"reasonKind":[[:space:]]*"platform_abstraction"'
run_runtime_plan_report_case "examples/hello" "compile.hxml" "portable" "selective" \
	'portable runtime plan define provenance artifacts' \
	'rust_hxrt_features=thread' \
	'"sourceKind":[[:space:]]*"define"' \
	'"source":[[:space:]]*"rust_hxrt_features"'
run_runtime_plan_report_case "examples/sys_net_loopback" "compile.hxml" "portable" "selective" \
	'portable runtime plan module+dependency provenance artifacts' \
	"" \
	'"sourceKind":[[:space:]]*"module"' \
	'"sourceKind":[[:space:]]*"dependency_edge"'
run_runtime_plan_report_case "test/negative/runtime_fallback_reason_dynamic" "compile.hxml" "portable" "selective" \
	'runtime fallback reason fixture records Dynamic semantics' \
	"" \
	"" \
	"" \
	'"reasonKind":[[:space:]]*"dynamic"' \
	'"sourceModule":[[:space:]]*"haxe[.]DynamicAccess"'
run_runtime_plan_report_case "examples/profile_storyboard" "compile.metal.hxml" "metal" "default_features" \
	'metal default-features runtime plan artifacts (profile_storyboard)' \
	'rust_hxrt_default_features'
run_runtime_plan_report_case "test/positive/metal_no_hxrt_minimal" "compile.hxml" "metal" "no_hxrt" \
	'metal no-hxrt runtime plan artifacts' \
	"" \
	"" \
	"" \
	'"requiresHxrt":[[:space:]]*false' \
	'"blockedByNoHxrt":[[:space:]]*false'
run_optimizer_plan_report_case "test/snapshot/string_clone_elision" "compile.hxml" "portable" \
	'portable optimizer plan report artifacts'
run_optimizer_plan_report_case "test/snapshot/for_array_alias_mutating" "compile.hxml" "portable" \
	'portable optimizer plan records alias-hazard skip for array iteration lowering' \
	'"id":[[:space:]]*"loop_optimizations\.skipped\.array_iter_borrowed\.desugared_for\.alias_hazard"'
run_optional_fallback_group "examples/profile_storyboard" "compile.metal.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'profile_storyboard metal fallback warning/top-module assertions' \
	'haxe\.ds\.(IntMap|StringMap):(2[0-9]|[3-9][0-9]|[1-9][0-9]{2,})' \
	'metal fallback top-modules keeps IntMap/StringMap fallback below 2 after typed map helper migration (profile_storyboard)' \
	'haxe\.ds\.(ObjectMap|EnumValueMap):(2[0-9]|[3-9][0-9]|[1-9][0-9]{2,})' \
	'metal fallback top-modules keeps ObjectMap/EnumValueMap fallback below 2 after typed map helper migration (profile_storyboard)' \
	'profile\.MetalRuntime:' \
	'metal fallback top-modules excludes profile.MetalRuntime after typed score lowering' \
	'Sys:' \
	'metal fallback top-modules excludes Sys after typed runtime wrapper migration (profile_storyboard)' \
	'sys\.io\.Stdout' \
	'metal fallback top-modules excludes Stdout after typed runtime wrapper migration (profile_storyboard)' \
	'sys\.io\.Stderr' \
	'metal fallback top-modules excludes Stderr after typed runtime wrapper migration (profile_storyboard)'
run_optional_fallback_case "test/snapshot/rust_hashmap" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'rust\.HashMapTools' \
	'metal fallback top-modules excludes rust.HashMapTools after typed hash map helper migration'
run_optional_fallback_group "test/snapshot/rust_vec" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'rust_vec metal fallback top-module assertions' \
	'rust\.VecTools' \
	'metal fallback top-modules excludes rust.VecTools after typed vec helper migration' \
	'rust\.IterTools' \
	'metal fallback top-modules excludes rust.IterTools after typed iter helper migration'
run_optional_fallback_group "test/snapshot/rust_path_time" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'rust_path_time metal fallback top-module assertions' \
	'rust\.PathBufTools' \
	'metal fallback top-modules excludes rust.PathBufTools after typed path helper migration' \
	'rust\.OsStringTools' \
	'metal fallback top-modules excludes rust.OsStringTools after typed os-string helper migration' \
	'rust\.DurationTools' \
	'metal fallback top-modules excludes rust.DurationTools after typed duration helper migration' \
	'rust\.InstantTools' \
	'metal fallback top-modules excludes rust.InstantTools after typed instant helper migration'
run_optional_fallback_group "test/snapshot/rust_array_slice_views" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'rust_array_slice_views metal fallback top-module assertions' \
	'rust\.SliceTools' \
	'metal fallback top-modules excludes rust.SliceTools after typed slice helper migration' \
	'rust\.MutSliceTools' \
	'metal fallback top-modules excludes rust.MutSliceTools after typed mut-slice helper migration' \
	'rust\.ArrayBorrow' \
	'metal fallback top-modules excludes rust.ArrayBorrow after typed array-borrow helper migration'
run_slice_view_output_shape_case "test/snapshot/rust_array_slice_views" "compile.hxml" \
	'metal Array slice-view helpers borrow storage without clone/materialization'
run_optional_fallback_case "test/positive/borrow_literal_derivation" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'' \
	'borrow region allows returned literals with owned derivations'
run_optional_fallback_case "test/positive/borrow_alias_derivation" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'' \
	'typed borrow region allows local aliases used for owned derivations'
run_optional_fallback_case "test/positive/borrow_wrapper_derivation" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'' \
	'typed borrow region allows owned values inside returned wrappers'
run_optional_fallback_case "test/positive/metal_raii_guard_scoped" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'' \
	'typed RAII guard scopes allow owned derivations'
run_optional_fallback_case "test/positive/borrow_mut_disjoint_scopes" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'' \
	'typed borrow region allows sequential same-source mutable scopes'
run_optional_fallback_case "test/snapshot/rust_borrow_ref" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'rust\.StringTools' \
	'metal fallback top-modules excludes rust.StringTools in borrow-ref snapshot after typed string helper migration'
run_optional_fallback_case "test/snapshot/rust_str_slice" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'rust\.StringTools' \
	'metal fallback top-modules excludes rust.StringTools in str-slice snapshot after typed string helper migration'
run_optional_fallback_case "test/snapshot/async_retry" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'Main:' \
	'metal fallback top-modules excludes Main in async_retry snapshot after typed async lowering migration'
run_optional_fallback_case "test/snapshot/async_select" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'Main:' \
	'metal fallback top-modules excludes Main in async_select snapshot after typed async lowering migration'
run_optional_fallback_case "test/snapshot/async_select" "compile.tokio.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'Main:' \
	'metal fallback top-modules excludes Main in async_select tokio snapshot after typed async lowering migration'
run_optional_fallback_case "test/snapshot/rust_async_tasks" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'Main:' \
	'metal fallback top-modules excludes Main in rust_async_tasks snapshot after typed async lowering migration'
run_optional_fallback_case "test/snapshot/rust_async_tasks" "compile.tokio.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'Main:' \
	'metal fallback top-modules excludes Main in rust_async_tasks tokio snapshot after typed async lowering migration'
run_optional_fallback_case "test/snapshot/metal_v1_smoke" "compile.metal.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'haxe\.io\.FPHelper' \
	'metal fallback top-modules excludes haxe.io.FPHelper after typed fp helper migration'
run_optional_fallback_group "examples/chat_loopback" "compile.metal.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'chat_loopback metal fallback top-module assertions' \
	'sys\.net\.Socket' \
	'metal fallback top-modules excludes sys.net.Socket after typed socket boundary migration' \
	'sys\.thread\.EventLoop:' \
	'metal fallback top-modules excludes sys.thread.EventLoop after typed thread runtime wrappers' \
	'sys\.thread\.Thread:' \
	'metal fallback top-modules excludes sys.thread.Thread after typed thread runtime wrappers' \
	'StringTools:' \
	'metal fallback top-modules excludes StringTools after removing raw std injection paths' \
	'rust\.test\.Assert' \
	'metal fallback top-modules excludes rust.test.Assert after typed assert native boundary migration' \
	'profile\.MetalRuntime:(4[0-9]*|[5-9][0-9]|[1-9][0-9]{2,})' \
	'metal fallback top-modules keeps profile.MetalRuntime raw fallback below 4 after typed fingerprint migration' \
	'app\.ChatUiApp:(3[0-9]|[4-9][0-9]|[1-9][0-9]{2,})' \
	'metal fallback top-modules keeps app.ChatUiApp raw fallback below 30 after typed generic static-call lowering migration' \
	'profile\.RemoteRuntime:(2[1-9]|[3-9][0-9]|[1-9][0-9]{2,})' \
	'metal fallback top-modules keeps profile.RemoteRuntime raw fallback below 21 after typed catch/downcast lowering'
run_no_hxrt_success_case "test/positive/metal_no_hxrt_minimal" "compile.hxml" \
	'rust_no_hxrt emits runtime-free minimal crate'
run_native_file_output_shape_case "test/positive/metal_no_hxrt_native_file" "compile.hxml" \
	'rust.fs.NativeFiles emits direct std::fs no-hxrt output'
run_native_tcp_output_shape_case "test/positive/metal_no_hxrt_native_tcp" "compile.hxml" \
	'rust.net.NativeTcp emits direct std::net no-hxrt output'
run_native_udp_output_shape_case "test/positive/metal_no_hxrt_native_udp" "compile.hxml" \
	'rust.net.NativeUdp emits direct std::net UDP no-hxrt output'
run_socket_error_output_shape_case "test/positive/metal_no_hxrt_socket_error" "compile.hxml" \
	'rust.net.SocketError emits typed no-hxrt socket errors'
run_udp_bytes_output_shape_case "test/positive/metal_no_hxrt_udp_bytes" "compile.hxml" \
	'rust.net.UdpSocket byte datagrams emit direct std::net no-hxrt output'
run_tcp_bytes_output_shape_case "test/positive/metal_no_hxrt_tcp_bytes" "compile.hxml" \
	'rust.net.TcpStream byte streams emit direct std::net no-hxrt output'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_native_process" "compile.hxml" \
	'rust.process.NativeCommands emits direct std::process no-hxrt output'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_command_output" "compile.hxml" \
	'rust.process.CommandOutput emits direct std::process::Output no-hxrt output'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_command_cwd" "compile.hxml" \
	'rust.process.NativeCommands current_dir emits direct std::process no-hxrt output'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_command_env" "compile.hxml" \
	'rust.process.NativeCommands env overrides emit direct std::process no-hxrt output'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_command_env_ops" "compile.hxml" \
	'rust.process.CommandEnv remove/clear emit direct std::process no-hxrt output'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_command_cwd_env" "compile.hxml" \
	'rust.process.NativeCommands cwd+env emits direct std::process no-hxrt output'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_command_stdin" "compile.hxml" \
	'rust.process.NativeCommands stdin emits direct std::process no-hxrt output'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_command_stdin_cwd_env" "compile.hxml" \
	'rust.process.NativeCommands stdin+cwd+env emits direct std::process no-hxrt output'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_command_spec" "compile.hxml" \
	'rust.process.CommandSpec emits direct std::process no-hxrt output'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_command_error" "compile.hxml" \
	'rust.process.CommandError emits typed no-hxrt command errors'
run_native_process_output_shape_case "test/positive/metal_no_hxrt_command_child" "compile.hxml" \
	'rust.process.CommandChild emits live no-hxrt child lifecycle'

echo "[metal-policy] ok"
