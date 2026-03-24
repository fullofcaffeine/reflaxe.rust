#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

echo "[ci] docs tracker sync guard"
npm run docs:check:progress

echo "[ci] docs entrypoint navigation guard"
npm run docs:check:navigation

echo "[ci] semantic confidence summary guard"
npm run docs:check:evidence

echo "[ci] rustfmt"
cargo fmt --check --all

echo "[ci] clippy"
cargo clippy --workspace --all-targets --locked -- -D warnings

echo "[ci] harness (snapshots + examples)"
bash scripts/ci/harness.sh

echo "[ci] upstream stdlib tier2 sweep"
bash test/run-upstream-stdlib-sweep.sh --tier tier2

gate_mode="${HXRT_PERF_GATE_MODE:-soft}"
echo "[ci] hxrt overhead benchmarks (gate mode: ${gate_mode})"
bash scripts/ci/perf-hxrt-overhead.sh --gate-mode "${gate_mode}"

echo "[ci] ok"
