#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
clean_script="$repo_root/scripts/ci/clean-artifacts.sh"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/clean-artifacts-test.XXXXXX")"

cleanup() {
  rm -rf "$tmp_root"
}

trap cleanup EXIT INT TERM

fail() {
  echo "[clean-artifacts-test] error: $*" >&2
  exit 1
}

seed_outputs() {
  mkdir -p \
    "$tmp_root/test/snapshot/snap_case/out" \
    "$tmp_root/test/snapshot/snap_case/out_metal" \
    "$tmp_root/test/semantic_diff/core_case/out" \
    "$tmp_root/test/semantic_diff_lanes/lane_case/out" \
    "$tmp_root/examples/demo/out" \
    "$tmp_root/examples/demo/out_ci"

  touch \
    "$tmp_root/test/snapshot/snap_case/out/Cargo.toml" \
    "$tmp_root/test/snapshot/snap_case/out_metal/Cargo.toml" \
    "$tmp_root/test/semantic_diff/core_case/out/Cargo.toml" \
    "$tmp_root/test/semantic_diff_lanes/lane_case/out/Cargo.toml" \
    "$tmp_root/examples/demo/out/Cargo.toml" \
    "$tmp_root/examples/demo/out_ci/Cargo.toml"
}

seed_caches() {
  mkdir -p \
    "$tmp_root/.cache/examples-target/debug" \
    "$tmp_root/.cache/snapshots-target/debug" \
    "$tmp_root/.cache/upstream-stdlib-target/debug" \
    "$tmp_root/.cache/package-smoke/repo" \
    "$tmp_root/.cache/package-smoke-target/debug" \
    "$tmp_root/.cache/template-smoke/project" \
    "$tmp_root/.cache/template-smoke-target/debug" \
    "$tmp_root/.cache/template-smoke-root-hx-target/debug" \
    "$tmp_root/.cache/perf-hxrt/results" \
    "$tmp_root/.cache/portable-native-import-diagnostics/out_json" \
    "$tmp_root/test/.cache/semantic-diff-target" \
    "$tmp_root/.cache/preserved-cache" \
    "$tmp_root/test/snapshot/snap_case/preserved" \
    "$tmp_root/examples/demo/preserved"

  touch \
    "$tmp_root/.cache/examples-target/debug/artifact" \
    "$tmp_root/.cache/snapshots-target/debug/artifact" \
    "$tmp_root/.cache/upstream-stdlib-target/debug/artifact" \
    "$tmp_root/.cache/package-smoke/repo/artifact" \
    "$tmp_root/.cache/package-smoke-target/debug/artifact" \
    "$tmp_root/.cache/template-smoke/project/artifact" \
    "$tmp_root/.cache/template-smoke-target/debug/artifact" \
    "$tmp_root/.cache/template-smoke-root-hx-target/debug/artifact" \
    "$tmp_root/.cache/perf-hxrt/results/current.json" \
    "$tmp_root/.cache/portable-native-import-diagnostics/out_json/Cargo.toml" \
    "$tmp_root/test/.cache/semantic-diff-target/artifact" \
    "$tmp_root/.cache/preserved-cache/artifact" \
    "$tmp_root/test/snapshot/snap_case/preserved/file" \
    "$tmp_root/examples/demo/preserved/file"
}

assert_absent() {
  local rel="$1"
  [[ ! -e "$tmp_root/$rel" ]] || fail "expected removed path to be absent: $rel"
}

assert_present() {
  local rel="$1"
  [[ -e "$tmp_root/$rel" ]] || fail "expected preserved path to exist: $rel"
}

assert_outputs_absent() {
  assert_absent "test/snapshot/snap_case/out"
  assert_absent "test/snapshot/snap_case/out_metal"
  assert_absent "test/semantic_diff/core_case/out"
  assert_absent "test/semantic_diff_lanes/lane_case/out"
  assert_absent "examples/demo/out"
  assert_absent "examples/demo/out_ci"
}

assert_caches_absent() {
  assert_absent ".cache/examples-target"
  assert_absent ".cache/snapshots-target"
  assert_absent ".cache/upstream-stdlib-target"
  assert_absent ".cache/package-smoke"
  assert_absent ".cache/package-smoke-target"
  assert_absent ".cache/template-smoke"
  assert_absent ".cache/template-smoke-target"
  assert_absent ".cache/template-smoke-root-hx-target"
  assert_absent ".cache/perf-hxrt"
  assert_absent ".cache/portable-native-import-diagnostics"
  assert_absent "test/.cache"
}

seed_outputs
seed_caches

CLEAN_ARTIFACTS_ROOT_DIR="$tmp_root" bash "$clean_script" --outputs >/dev/null
assert_outputs_absent
assert_present ".cache/examples-target"
assert_present ".cache/perf-hxrt"
assert_present "test/.cache"
assert_present ".cache/preserved-cache/artifact"
assert_present "test/snapshot/snap_case/preserved/file"
assert_present "examples/demo/preserved/file"

seed_outputs
CLEAN_ARTIFACTS_ROOT_DIR="$tmp_root" bash "$clean_script" --all >/dev/null
assert_outputs_absent
assert_caches_absent
assert_present ".cache/preserved-cache/artifact"
assert_present "test/snapshot/snap_case/preserved/file"
assert_present "examples/demo/preserved/file"

echo "[clean-artifacts-test] ok"
