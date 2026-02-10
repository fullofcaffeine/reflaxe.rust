#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

echo "[ci] rustfmt"
cargo fmt --check --all

echo "[ci] clippy"
cargo clippy --workspace --all-targets --locked -- -D warnings

echo "[ci] harness (snapshots + examples)"
bash scripts/ci/harness.sh

echo "[ci] ok"
