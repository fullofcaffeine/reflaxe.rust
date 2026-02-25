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

run_warning_case_absent() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local required_regex="$3"
	local forbidden_regex="$4"
	local expected_count="$5"
	local failure_label="$6"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_dir="$fixture_dir/out_policy_warning_absent"
	local log_file="$fixture_dir/.compile_absent.log"

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
}

run_report_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local failure_label="$3"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_a="$fixture_dir/out_policy_report_a"
	local out_b="$fixture_dir/out_policy_report_b"
	local log_a="$fixture_dir/.compile_report_a.log"
	local log_b="$fixture_dir/.compile_report_b.log"

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
}

run_profile_contract_report_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local expected_profile="$3"
	local failure_label="$4"
	local expected_strict_boundary="${5:-}"
	local expected_strict_examples="${6:-}"
	local expected_metal_fallback_allowed="${7:-}"
	local expected_metal_contract_hard_error="${8:-}"
	local expected_no_hxrt="${9:-}"
	local expected_async_enabled="${10:-}"
	local expected_nullable_strings="${11:-}"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_a="$fixture_dir/out_profile_contract_a"
	local out_b="$fixture_dir/out_profile_contract_b"
	local log_a="$fixture_dir/.compile_profile_a.log"
	local log_b="$fixture_dir/.compile_profile_b.log"

	rm -rf "$out_a" "$out_b"
	rm -f "$log_a" "$log_b"

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_profile_contract_report -D rust_output=out_profile_contract_a) >"$log_a" 2>&1
	local status_a=$?
	set -e
	if [[ "$status_a" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label} (run A)."
		sed "s|$root_dir|.|g" "$log_a"
		exit 1
	fi

	set +e
	(cd "$fixture_dir" && haxe "$hxml_file" -D rust_no_build -D rust_profile_contract_report -D rust_output=out_profile_contract_b) >"$log_b" 2>&1
	local status_b=$?
	set -e
	if [[ "$status_b" -ne 0 ]]; then
		echo "[metal-policy] error: expected compile success for ${failure_label} (run B)."
		sed "s|$root_dir|.|g" "$log_b"
		exit 1
	fi

	local json_a="$out_a/profile_contract.json"
	local md_a="$out_a/profile_contract.md"
	local json_b="$out_b/profile_contract.json"
	local md_b="$out_b/profile_contract.md"

	if [[ ! -f "$json_a" || ! -f "$md_a" ]]; then
		echo "[metal-policy] error: expected profile contract artifacts for ${failure_label} (run A)."
		exit 1
	fi
	if [[ ! -f "$json_b" || ! -f "$md_b" ]]; then
		echo "[metal-policy] error: expected profile contract artifacts for ${failure_label} (run B)."
		exit 1
	fi

	if ! match_regex '"schemaVersion":[[:space:]]*1' "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing schemaVersion for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex "\"profile\":[[:space:]]*\"${expected_profile}\"" "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing expected profile for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"strictBoundary":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing strictBoundary for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"strictExamples":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing strictExamples for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"metalFallbackAllowed":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing metalFallbackAllowed for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"metalContractHardError":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing metalContractHardError for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"noHxrt":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing noHxrt for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"asyncEnabled":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing asyncEnabled for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"nullableStrings":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing nullableStrings for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"warnings":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing warnings array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"errors":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: profile_contract.json missing errors array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '^# Profile Contract Report' "$md_a"; then
		echo "[metal-policy] error: profile_contract.md missing title for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Warnings' "$md_a"; then
		echo "[metal-policy] error: profile_contract.md missing warnings section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Errors' "$md_a"; then
		echo "[metal-policy] error: profile_contract.md missing errors section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- strict boundary: \`(yes|no)\`" "$md_a"; then
		echo "[metal-policy] error: profile_contract.md missing strict-boundary summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex "^- no hxrt: \`(yes|no)\`" "$md_a"; then
		echo "[metal-policy] error: profile_contract.md missing no-hxrt summary for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi

	if [[ -n "$expected_strict_boundary" ]] && ! match_regex "\"strictBoundary\":[[:space:]]*${expected_strict_boundary}" "$json_a"; then
		echo "[metal-policy] error: profile_contract.json strictBoundary mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_strict_examples" ]] && ! match_regex "\"strictExamples\":[[:space:]]*${expected_strict_examples}" "$json_a"; then
		echo "[metal-policy] error: profile_contract.json strictExamples mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_metal_fallback_allowed" ]] && ! match_regex "\"metalFallbackAllowed\":[[:space:]]*${expected_metal_fallback_allowed}" "$json_a"; then
		echo "[metal-policy] error: profile_contract.json metalFallbackAllowed mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_metal_contract_hard_error" ]] \
		&& ! match_regex "\"metalContractHardError\":[[:space:]]*${expected_metal_contract_hard_error}" "$json_a"; then
		echo "[metal-policy] error: profile_contract.json metalContractHardError mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_no_hxrt" ]] && ! match_regex "\"noHxrt\":[[:space:]]*${expected_no_hxrt}" "$json_a"; then
		echo "[metal-policy] error: profile_contract.json noHxrt mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_async_enabled" ]] && ! match_regex "\"asyncEnabled\":[[:space:]]*${expected_async_enabled}" "$json_a"; then
		echo "[metal-policy] error: profile_contract.json asyncEnabled mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_nullable_strings" ]] && ! match_regex "\"nullableStrings\":[[:space:]]*${expected_nullable_strings}" "$json_a"; then
		echo "[metal-policy] error: profile_contract.json nullableStrings mismatch for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi

	if ! cmp -s "$json_a" "$json_b"; then
		echo "[metal-policy] error: profile_contract.json is non-deterministic across runs for ${failure_label}."
		diff -u "$json_a" "$json_b" || true
		exit 1
	fi
	if ! cmp -s "$md_a" "$md_b"; then
		echo "[metal-policy] error: profile_contract.md is non-deterministic across runs for ${failure_label}."
		diff -u "$md_a" "$md_b" || true
		exit 1
	fi

	rm -f "$log_a" "$log_b"
	rm -rf "$out_a" "$out_b"
}

run_hxrt_plan_report_case() {
	local fixture_rel="$1"
	local hxml_file="$2"
	local expected_profile="$3"
	local expected_mode="$4"
	local failure_label="$5"
	local extra_define="${6:-}"
	local expected_reason_regex="${7:-}"
	local expected_reason_regex_2="${8:-}"
	local fixture_dir="$root_dir/$fixture_rel"
	local out_a="$fixture_dir/out_hxrt_plan_a"
	local out_b="$fixture_dir/out_hxrt_plan_b"
	local log_a="$fixture_dir/.compile_hxrt_plan_a.log"
	local log_b="$fixture_dir/.compile_hxrt_plan_b.log"

	rm -rf "$out_a" "$out_b"
	rm -f "$log_a" "$log_b"

	local cmd_a=(haxe "$hxml_file" -D rust_no_build -D rust_hxrt_plan_report -D rust_output=out_hxrt_plan_a)
	local cmd_b=(haxe "$hxml_file" -D rust_no_build -D rust_hxrt_plan_report -D rust_output=out_hxrt_plan_b)
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

	local json_a="$out_a/hxrt_plan.json"
	local md_a="$out_a/hxrt_plan.md"
	local json_b="$out_b/hxrt_plan.json"
	local md_b="$out_b/hxrt_plan.md"

	if [[ ! -f "$json_a" || ! -f "$md_a" ]]; then
		echo "[metal-policy] error: expected hxrt plan artifacts for ${failure_label} (run A)."
		exit 1
	fi
	if [[ ! -f "$json_b" || ! -f "$md_b" ]]; then
		echo "[metal-policy] error: expected hxrt plan artifacts for ${failure_label} (run B)."
		exit 1
	fi

	if ! match_regex '"schemaVersion":[[:space:]]*1' "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing schemaVersion for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex "\"profile\":[[:space:]]*\"${expected_profile}\"" "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing expected profile for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex "\"mode\":[[:space:]]*\"${expected_mode}\"" "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing expected mode for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"selectedFeatures":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing selectedFeatures for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"manualFeatures":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing manualFeatures for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"noHxrt":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing noHxrt for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"useDefaultFeatures":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing useDefaultFeatures for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"inferenceDisabled":[[:space:]]*(true|false)' "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing inferenceDisabled for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if ! match_regex '"reasons":[[:space:]]*\[' "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing reasons array for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_reason_regex" ]] && ! match_regex "$expected_reason_regex" "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing expected reason pattern for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ -n "$expected_reason_regex_2" ]] && ! match_regex "$expected_reason_regex_2" "$json_a"; then
		echo "[metal-policy] error: hxrt_plan.json missing second expected reason pattern for ${failure_label}."
		sed "s|$root_dir|.|g" "$json_a"
		exit 1
	fi
	if [[ "$expected_mode" == "no_hxrt" ]]; then
		if ! match_regex '"noHxrt":[[:space:]]*true' "$json_a"; then
			echo "[metal-policy] error: hxrt_plan.json expected noHxrt=true for no_hxrt mode (${failure_label})."
			sed "s|$root_dir|.|g" "$json_a"
			exit 1
		fi
		if ! match_regex '"hxrtDependencyLine":[[:space:]]*""' "$json_a"; then
			echo "[metal-policy] error: hxrt_plan.json expected empty dependency line for no_hxrt mode (${failure_label})."
			sed "s|$root_dir|.|g" "$json_a"
			exit 1
		fi
	else
		if ! match_regex '"noHxrt":[[:space:]]*false' "$json_a"; then
			echo "[metal-policy] error: hxrt_plan.json expected noHxrt=false for ${expected_mode} mode (${failure_label})."
			sed "s|$root_dir|.|g" "$json_a"
			exit 1
		fi
	fi
	if [[ "$expected_mode" == "default_features" ]]; then
		if ! match_regex '"useDefaultFeatures":[[:space:]]*true' "$json_a"; then
			echo "[metal-policy] error: hxrt_plan.json expected useDefaultFeatures=true for default_features mode (${failure_label})."
			sed "s|$root_dir|.|g" "$json_a"
			exit 1
		fi
	else
		if ! match_regex '"useDefaultFeatures":[[:space:]]*false' "$json_a"; then
			echo "[metal-policy] error: hxrt_plan.json expected useDefaultFeatures=false for ${expected_mode} mode (${failure_label})."
			sed "s|$root_dir|.|g" "$json_a"
			exit 1
		fi
	fi
	if ! match_regex '^# HXRT Runtime Plan' "$md_a"; then
		echo "[metal-policy] error: hxrt_plan.md missing title for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Selected features' "$md_a"; then
		echo "[metal-policy] error: hxrt_plan.md missing selected features section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Manual features' "$md_a"; then
		echo "[metal-policy] error: hxrt_plan.md missing manual features section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Feature reasons' "$md_a"; then
		echo "[metal-policy] error: hxrt_plan.md missing feature reasons section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi
	if ! match_regex '^## Dependency line' "$md_a"; then
		echo "[metal-policy] error: hxrt_plan.md missing dependency line section for ${failure_label}."
		sed "s|$root_dir|.|g" "$md_a"
		exit 1
	fi

	if ! cmp -s "$json_a" "$json_b"; then
		echo "[metal-policy] error: hxrt_plan.json is non-deterministic across runs for ${failure_label}."
		diff -u "$json_a" "$json_b" || true
		exit 1
	fi
	if ! cmp -s "$md_a" "$md_b"; then
		echo "[metal-policy] error: hxrt_plan.md is non-deterministic across runs for ${failure_label}."
		diff -u "$md_a" "$md_b" || true
		exit 1
	fi

	rm -f "$log_a" "$log_b"
	rm -rf "$out_a" "$out_b"
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
run_negative_case "test/negative/metal_island_dynamic_access" 'Metal island violation in module `Main`.*dynamic_boundary/dynamic_access' \
	'@:rustMetal module rejects dynamic boundary usage in portable profile'
run_negative_case "test/negative/metal_island_raw_fallback" 'Metal island violation in module `Main`.*raw Rust expression node\(s\) \(`ERaw`\)' \
	'@:rustMetal module rejects raw fallback codegen in portable profile'
run_negative_case "test/negative/metal_nullable_strings" 'metal profile does not allow -D rust_string_nullable in metal-clean mode' \
	'rust_string_nullable under metal profile'
run_negative_case "test/negative/metal_no_hxrt_requires_metal" '`-D rust_no_hxrt` currently requires `-D reflaxe_rust_profile=metal`\.' \
	'rust_no_hxrt requires metal profile'
run_negative_case "test/negative/metal_no_hxrt_runtime_boundary" '`-D rust_no_hxrt` violation in module' \
	'rust_no_hxrt rejects runtime-dependent output'
run_negative_case "test/negative/async_preview_removed" '`-D rust_async_preview` was removed\. Use `-D rust_async`\.' \
	'rust_async_preview define removed'
run_negative_case "test/negative/profile_removed_idiomatic" 'Unknown `-D reflaxe_rust_profile=idiomatic`\. Expected portable\|metal\.' \
	'idiomatic profile selector removed'
run_negative_case "test/negative/profile_removed_rusty" 'Unknown `-D reflaxe_rust_profile=rusty`\. Expected portable\|metal\.' \
	'rusty profile selector removed'
run_negative_case "test/negative/send_sync_borrow_capture" 'Rust concurrency contract violation: sys\.thread\.Thread\.create\(job\) captures `borrowed` with borrowed type `rust\.Ref<T>`' \
	'spawn closure captures borrow-only value under rust_send_sync_strict'
run_warning_case "test/negative/metal_dynamic_access" "compile.fallback.hxml" 'Rust profile contract: metal profile forbids haxe\.DynamicAccess runtime map semantics' \
	'1' 'haxe.DynamicAccess warning in explicit metal fallback mode'
run_warning_case "test/negative/metal_dynamic_access" "compile.viability.hxml" 'Metal viability: overall score [0-9]+/100, modules=[0-9]+, ready=[0-9]+, blockers=[0-9]+\.' \
	'1' 'metal viability summary warning output'
run_report_case "test/negative/metal_dynamic_access" "compile.viability.hxml" \
	'metal viability deterministic report artifacts'
run_profile_contract_report_case "examples/hello" "compile.hxml" "portable" \
	'portable profile contract report artifacts' \
	'false' 'true' 'false' 'false' 'false' 'false' 'true'
run_profile_contract_report_case "examples/hello" "compile.metal.hxml" "metal" \
	'metal profile contract report artifacts' \
	'true' 'true' 'true' 'false' 'false' 'false' 'false'
run_profile_contract_report_case "test/positive/metal_no_hxrt_minimal" "compile.hxml" "metal" \
	'metal no-hxrt profile contract report artifacts' \
	'true' 'false' 'false' 'true' 'true' 'false' 'false'
run_hxrt_plan_report_case "examples/hello" "compile.hxml" "portable" "selective" \
	'portable hxrt plan report artifacts'
run_hxrt_plan_report_case "examples/hello" "compile.hxml" "portable" "selective" \
	'portable hxrt plan report define provenance artifacts' \
	'rust_hxrt_features=thread' \
	'"sourceKind":[[:space:]]*"define"' \
	'"source":[[:space:]]*"rust_hxrt_features"'
run_hxrt_plan_report_case "examples/sys_net_loopback" "compile.hxml" "portable" "selective" \
	'portable hxrt plan report module+dependency provenance artifacts' \
	"" \
	'"sourceKind":[[:space:]]*"module"' \
	'"sourceKind":[[:space:]]*"dependency_edge"'
run_hxrt_plan_report_case "examples/hello" "compile.metal.hxml" "metal" "default_features" \
	'metal default-features hxrt plan report artifacts' \
	'rust_hxrt_default_features'
run_hxrt_plan_report_case "test/positive/metal_no_hxrt_minimal" "compile.hxml" "metal" "no_hxrt" \
	'metal no-hxrt plan report artifacts'
run_warning_case "examples/hello" "compile.metal.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'1' 'single aggregated metal fallback warning'
run_warning_case_absent "examples/hello" "compile.metal.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'haxe\.ds\.(IntMap|StringMap)' \
	'1' 'metal fallback top-modules excludes IntMap/StringMap after typed map helper migration'
run_warning_case_absent "examples/hello" "compile.metal.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'haxe\.ds\.(ObjectMap|EnumValueMap)' \
	'1' 'metal fallback top-modules excludes ObjectMap/EnumValueMap after typed map helper migration'
run_warning_case_absent "test/snapshot/rusty_hashmap" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'rust\.HashMapTools' \
	'1' 'metal fallback top-modules excludes rust.HashMapTools after typed hash map helper migration'
run_warning_case_absent "test/snapshot/rusty_vec" "compile.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'rust\.VecTools' \
	'1' 'metal fallback top-modules excludes rust.VecTools after typed vec helper migration'
run_warning_case_absent "examples/hello" "compile.metal.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'Sys:' \
	'1' 'metal fallback top-modules excludes Sys after typed runtime wrapper migration'
run_warning_case_absent "examples/hello" "compile.metal.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'sys\.io\.Stdout' \
	'1' 'metal fallback top-modules excludes Stdout after typed runtime wrapper migration'
run_warning_case_absent "examples/hello" "compile.metal.hxml" 'Metal fallback active: generated output contains [0-9]+ raw Rust expression node\(s\) \(`ERaw`\) across [0-9]+ module\(s\)\.' \
	'sys\.io\.Stderr' \
	'1' 'metal fallback top-modules excludes Stderr after typed runtime wrapper migration'
run_no_hxrt_success_case "test/positive/metal_no_hxrt_minimal" "compile.hxml" \
	'rust_no_hxrt emits runtime-free minimal crate'

echo "[metal-policy] ok"
