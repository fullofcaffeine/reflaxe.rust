#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

baseline_file="${METAL_IDIOM_BASELINE_FILE:-$root_dir/scripts/ci/metal-idiom-baseline.json}"
update_baseline=0

usage() {
	cat <<'EOUSAGE'
Usage: scripts/ci/check-metal-idiom-counts.sh [--update-baseline]

Compiles a curated metal/output-shape fixture suite and compares deterministic
idiom counters against a committed baseline.

Modes:
  default            Compare current counts vs baseline and fail on regressions.
  --update-baseline  Recompute baseline from current counts and overwrite file.

Environment:
  METAL_IDIOM_BASELINE_FILE  Override baseline JSON path.
EOUSAGE
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--update-baseline)
			update_baseline=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "[metal-idiom] error: unknown arg: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if ! command -v node >/dev/null 2>&1; then
	echo "[metal-idiom] error: node is required" >&2
	exit 2
fi

# Case format:
# id|relative_dir|hxml|out_dir|selected_rs_files_csv|minVec|minOption|minResult|minSlice|minBorrow
cases=(
	"rust_vec_native_shapes|test/snapshot/rust_vec|compile.hxml|out_idiom_guard_rust_vec|main.rs,vec_tools.rs,iter_tools.rs|1|1|1|0|1"
	"array_slice_view_shapes|test/snapshot/rust_array_slice_views|compile.hxml|out_idiom_guard_slice_views|main.rs,array_borrow_tools.rs|0|0|0|1|1"
	"portable_facade_option_result_shapes|test/snapshot/portable_facade_native_option_result|compile.hxml|out_idiom_guard_portable_facade|main.rs|0|1|1|0|0"
	"metal_no_hxrt_lower_bound|test/positive/metal_no_hxrt_minimal|compile.hxml|out_idiom_guard_no_hxrt|main.rs,duration_tools.rs|0|0|0|0|0"
)

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
metrics_json="$tmp_dir/current_metrics.json"

printf '{\n  "schemaVersion": 1,\n  "cases": {\n' >"$metrics_json"
case_index=0
for entry in "${cases[@]}"; do
	IFS='|' read -r case_id case_rel case_hxml case_out selected_files min_vec min_option min_result min_slice min_borrow <<<"$entry"
	case_dir="$root_dir/$case_rel"
	out_dir="$case_dir/$case_out"
	log_file="$tmp_dir/${case_id}.log"

	if [[ ! -d "$case_dir" ]]; then
		echo "[metal-idiom] error: missing case directory: $case_rel" >&2
		exit 2
	fi
	if [[ ! -f "$case_dir/$case_hxml" ]]; then
		echo "[metal-idiom] error: missing case hxml: $case_rel/$case_hxml" >&2
		exit 2
	fi

	rm -rf "$out_dir"

	set +e
	(
		cd "$case_dir"
		haxe "$case_hxml" -D rust_no_build -D rust_output="$case_out"
	) >"$log_file" 2>&1
	compile_status=$?
	set -e

	if [[ "$compile_status" -ne 0 ]]; then
		echo "[metal-idiom] error: compile failed for case '$case_id' ($case_rel/$case_hxml)" >&2
		sed "s|$root_dir|.|g" "$log_file" >&2
		exit 1
	fi

	metrics_case_json="$tmp_dir/${case_id}.json"
	node - "$out_dir" "$selected_files" "$min_vec" "$min_option" "$min_result" "$min_slice" "$min_borrow" >"$metrics_case_json" <<'NODE'
const fs = require("fs");
const path = require("path");

const outDir = process.argv[2];
const selectedFiles = process.argv[3].split(",").filter((value) => value.length > 0);
const requiredMinimums = {
  vecShapes: Number(process.argv[4]),
  optionShapes: Number(process.argv[5]),
  resultShapes: Number(process.argv[6]),
  sliceShapes: Number(process.argv[7]),
  borrowTokens: Number(process.argv[8]),
};

for (const [name, value] of Object.entries(requiredMinimums)) {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`invalid required minimum for ${name}: ${value}`);
  }
}

let text = "";
for (const rel of selectedFiles) {
  const filePath = path.join(outDir, "src", rel);
  if (!fs.existsSync(filePath)) {
    throw new Error(`missing selected generated source: src/${rel}`);
  }
  text += fs.readFileSync(filePath, "utf8");
  text += "\n";
}

function count(pattern) {
  const matches = text.match(pattern);
  return matches ? matches.length : 0;
}

const counts = {
  hxrtPathRefs: count(/\bhxrt::/g),
  semanticHxrtFallbackRefs: count(/\bhxrt::(?:dynamic|array|anon|exception|string|thread|async_|io|net|process|sys|bytes|fs|db|ssl)\b/g),
  dynamicRefs: count(/\bhxrt::dynamic\b|\bDynamic\b/g),
  rawERawMarkers: count(/\bERaw\b/g),
  cloneCalls: count(/\.clone\s*\(/g),
  borrowTokens: count(/\.borrow(?:_mut)?\s*\(|&\s*(?:mut\s+)?(?:\[|[A-Za-z_])/g),
  vecShapes: count(/\bVec\s*</g),
  optionShapes: count(/\bOption\s*</g),
  resultShapes: count(/\bResult\s*</g),
  sliceShapes: count(/&\s*(?:mut\s*)?\[[^\]]+\]/g),
};

process.stdout.write(`${JSON.stringify({
  selectedFiles,
  requiredMinimums,
  counts,
})}\n`);
NODE

	if [[ "$case_index" -gt 0 ]]; then
		printf ',\n' >>"$metrics_json"
	fi
	printf '    "%s": ' "$case_id" >>"$metrics_json"
	cat "$metrics_case_json" >>"$metrics_json"
	case_index=$((case_index + 1))

	rm -rf "$out_dir"
done
printf '\n  }\n}\n' >>"$metrics_json"

# Normalize formatting for stable diffs and readable baseline updates.
node - "$metrics_json" <<'NODE'
const fs = require("fs");
const path = process.argv[2];
const payload = JSON.parse(fs.readFileSync(path, "utf8"));
fs.writeFileSync(path, `${JSON.stringify(payload, null, 2)}\n`);
NODE

if [[ "$update_baseline" -eq 1 ]]; then
	mkdir -p "$(dirname "$baseline_file")"
	cp "$metrics_json" "$baseline_file"
	echo "[metal-idiom] updated baseline: ${baseline_file#$root_dir/}"
	exit 0
fi

if [[ ! -f "$baseline_file" ]]; then
	echo "[metal-idiom] error: baseline file not found: ${baseline_file#$root_dir/}" >&2
	echo "[metal-idiom] hint: run with --update-baseline" >&2
	exit 1
fi

node - "$baseline_file" "$metrics_json" <<'NODE'
const fs = require("fs");
const baselinePath = process.argv[2];
const currentPath = process.argv[3];
const baseline = JSON.parse(fs.readFileSync(baselinePath, "utf8"));
const current = JSON.parse(fs.readFileSync(currentPath, "utf8"));
const errors = [];
const warnings = [];

if (baseline.schemaVersion !== 1) {
  errors.push(`unsupported baseline schemaVersion: ${baseline.schemaVersion}`);
}
if (current.schemaVersion !== 1) {
  errors.push(`unsupported current schemaVersion: ${current.schemaVersion}`);
}

const baselineCases = baseline.cases || {};
const currentCases = current.cases || {};
const bloatFields = [
  "hxrtPathRefs",
  "semanticHxrtFallbackRefs",
  "dynamicRefs",
  "rawERawMarkers",
  "cloneCalls",
  "borrowTokens",
];

for (const [caseId, expected] of Object.entries(baselineCases)) {
  const got = currentCases[caseId];
  if (!got) {
    errors.push(`missing current case: ${caseId}`);
    continue;
  }

  if (JSON.stringify(got.selectedFiles || []) !== JSON.stringify(expected.selectedFiles || [])) {
    errors.push(`${caseId}: selected source files changed; update baseline with rationale`);
  }
  if (JSON.stringify(got.requiredMinimums || {}) !== JSON.stringify(expected.requiredMinimums || {})) {
    errors.push(`${caseId}: required minimums changed; update baseline with rationale`);
  }

  const gotCounts = got.counts || {};
  const expectedCounts = expected.counts || {};
  for (const field of bloatFields) {
    const expectedCount = Number(expectedCounts[field] || 0);
    const gotCount = Number(gotCounts[field] || 0);
    if (gotCount > expectedCount) {
      errors.push(`${caseId}: ${field} regression (${gotCount} > baseline ${expectedCount})`);
    } else if (gotCount < expectedCount) {
      warnings.push(`${caseId}: ${field} improved (${gotCount} < baseline ${expectedCount})`);
    }
  }

  const requiredMinimums = got.requiredMinimums || {};
  for (const [field, rawMinimum] of Object.entries(requiredMinimums)) {
    const minimum = Number(rawMinimum || 0);
    const gotCount = Number(gotCounts[field] || 0);
    if (gotCount < minimum) {
      errors.push(`${caseId}: ${field} below required minimum (${gotCount} < ${minimum})`);
    }
  }
}

for (const caseId of Object.keys(currentCases)) {
  if (!Object.prototype.hasOwnProperty.call(baselineCases, caseId)) {
    warnings.push(`new untracked current case: ${caseId}`);
  }
}

for (const line of warnings) {
  console.log(`[metal-idiom] warn: ${line}`);
}
if (errors.length > 0) {
  for (const line of errors) {
    console.error(`[metal-idiom] error: ${line}`);
  }
  process.exit(1);
}
console.log("[metal-idiom] ok");
NODE
