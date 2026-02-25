#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

baseline_file="${METAL_FALLBACK_BASELINE_FILE:-$root_dir/scripts/ci/metal-fallback-baseline.json}"
update_baseline=0

usage() {
	cat <<'EOUSAGE'
Usage: scripts/ci/check-metal-fallback-counts.sh [--update-baseline]

Runs a small set of metal-oriented compile fixtures and compares emitted fallback
warning counts against a committed baseline.

Modes:
  default            Compare current counts vs baseline and fail on regressions.
  --update-baseline  Recompute baseline from current counts and overwrite file.

Environment:
  METAL_FALLBACK_BASELINE_FILE  Override baseline JSON path.
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
			echo "[metal-fallback] error: unknown arg: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if ! command -v node >/dev/null 2>&1; then
	echo "[metal-fallback] error: node is required" >&2
	exit 2
fi

# Case format: id|relative_dir|hxml|out_dir
cases=(
	"hello_metal|examples/hello|compile.metal.hxml|out_fallback_guard_hello"
	"rusty_concurrent_snapshot|test/snapshot/rusty_concurrent|compile.hxml|out_fallback_guard_rusty_concurrent"
	"chat_loopback_metal|examples/chat_loopback|compile.metal.hxml|out_fallback_guard_chat"
)

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
metrics_json="$tmp_dir/current_metrics.json"

printf '{\n  "schemaVersion": 1,\n  "cases": {\n' >"$metrics_json"
case_index=0
for entry in "${cases[@]}"; do
	IFS='|' read -r case_id case_rel case_hxml case_out <<<"$entry"
	case_dir="$root_dir/$case_rel"
	log_file="$tmp_dir/${case_id}.log"

	if [[ ! -d "$case_dir" ]]; then
		echo "[metal-fallback] error: missing case directory: $case_rel" >&2
		exit 2
	fi
	if [[ ! -f "$case_dir/$case_hxml" ]]; then
		echo "[metal-fallback] error: missing case hxml: $case_rel/$case_hxml" >&2
		exit 2
	fi

	rm -rf "$case_dir/$case_out"

	set +e
	(
		cd "$case_dir"
		haxe "$case_hxml" -D rust_no_build -D rust_output="$case_out"
	) >"$log_file" 2>&1
	status=$?
	set -e

	if [[ "$status" -ne 0 ]]; then
		echo "[metal-fallback] error: compile failed for case '$case_id' ($case_rel/$case_hxml)" >&2
		sed "s|$root_dir|.|g" "$log_file" >&2
		exit 1
	fi

	metrics_case_json="$tmp_dir/${case_id}.json"
	node - "$log_file" >"$metrics_case_json" <<'NODE'
const fs = require("fs");
const logPath = process.argv[2];
const text = fs.readFileSync(logPath, "utf8");
const warningRegex = /Metal fallback active: generated output contains (\d+) raw Rust expression node\(s\) \(`ERaw`\) across (\d+) module\(s\)\. Top fallback modules: ([^\n]+)/;
const m = text.match(warningRegex);
let rawNodes = 0;
let moduleCount = 0;
const topModules = {};
if (m) {
  rawNodes = Number(m[1]);
  moduleCount = Number(m[2]);
  const parts = String(m[3]).split(",");
  for (const part of parts) {
    const trimmed = part.trim();
    if (trimmed.length === 0) continue;
    const idx = trimmed.lastIndexOf(":");
    if (idx <= 0) continue;
    const name = trimmed.slice(0, idx).trim();
    const value = Number(trimmed.slice(idx + 1).trim());
    if (!Number.isFinite(value)) continue;
    topModules[name] = value;
  }
}
const out = {
  rawNodes,
  moduleCount,
  topModules,
};
process.stdout.write(`${JSON.stringify(out)}\n`);
NODE

	if [[ "$case_index" -gt 0 ]]; then
		printf ',\n' >>"$metrics_json"
	fi
	printf '    "%s": ' "$case_id" >>"$metrics_json"
	cat "$metrics_case_json" >>"$metrics_json"
	case_index=$((case_index + 1))

	rm -rf "$case_dir/$case_out"

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
	echo "[metal-fallback] updated baseline: ${baseline_file#$root_dir/}"
	exit 0
fi

if [[ ! -f "$baseline_file" ]]; then
	echo "[metal-fallback] error: baseline file not found: ${baseline_file#$root_dir/}" >&2
	echo "[metal-fallback] hint: run with --update-baseline" >&2
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

for (const [caseId, expected] of Object.entries(baselineCases)) {
  const got = currentCases[caseId];
  if (!got) {
    errors.push(`missing current case: ${caseId}`);
    continue;
  }

  const expectedRaw = Number(expected.rawNodes || 0);
  const gotRaw = Number(got.rawNodes || 0);
  if (gotRaw > expectedRaw) {
    errors.push(`${caseId}: rawNodes regression (${gotRaw} > baseline ${expectedRaw})`);
  } else if (gotRaw < expectedRaw) {
    warnings.push(`${caseId}: improved rawNodes (${gotRaw} < baseline ${expectedRaw})`);
  }

  const expectedTop = expected.topModules || {};
  const gotTop = got.topModules || {};
  for (const [moduleName, expectedCountRaw] of Object.entries(expectedTop)) {
    const expectedCount = Number(expectedCountRaw);
    const gotCount = Number(gotTop[moduleName] || 0);
    if (gotCount > expectedCount) {
      errors.push(`${caseId}: module '${moduleName}' regression (${gotCount} > baseline ${expectedCount})`);
    } else if (gotCount < expectedCount) {
      warnings.push(`${caseId}: module '${moduleName}' improved (${gotCount} < baseline ${expectedCount})`);
    }
  }
}

for (const caseId of Object.keys(currentCases)) {
  if (!Object.prototype.hasOwnProperty.call(baselineCases, caseId)) {
    warnings.push(`new untracked current case: ${caseId}`);
  }
}

for (const line of warnings) {
  console.log(`[metal-fallback] warn: ${line}`);
}
if (errors.length > 0) {
  for (const line of errors) {
    console.error(`[metal-fallback] error: ${line}`);
  }
  process.exit(1);
}
console.log("[metal-fallback] ok");
NODE
