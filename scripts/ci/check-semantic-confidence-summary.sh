#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

tmp_a="$(mktemp -d "${TMPDIR:-/tmp}/semantic-confidence-a.XXXXXX")"
tmp_b="$(mktemp -d "${TMPDIR:-/tmp}/semantic-confidence-b.XXXXXX")"

cleanup() {
  rm -rf "$tmp_a" "$tmp_b"
}
trap cleanup EXIT

echo "[semantic-confidence] generate run A"
node scripts/ci/generate-semantic-confidence-summary.js --write --out-dir "$tmp_a" >/dev/null

echo "[semantic-confidence] generate run B"
node scripts/ci/generate-semantic-confidence-summary.js --write --out-dir "$tmp_b" >/dev/null

diff -u "$tmp_a/semantic-confidence-summary.json" "$tmp_b/semantic-confidence-summary.json"
diff -u "$tmp_a/semantic-confidence-summary.md" "$tmp_b/semantic-confidence-summary.md"

echo "[semantic-confidence] repository artifact check"
node scripts/ci/generate-semantic-confidence-summary.js --check

echo "[semantic-confidence] ok"
