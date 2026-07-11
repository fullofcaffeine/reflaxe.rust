#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-rust-artifact-contract.XXXXXX")"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

haxe_bin="${HAXE_BIN:-}"
if [[ -z "$haxe_bin" ]]; then
  if [[ -x "$root_dir/node_modules/.bin/haxe" ]]; then
    haxe_bin="$root_dir/node_modules/.bin/haxe"
  else
    haxe_bin="haxe"
  fi
fi

structured_dir="$root_dir/test/contract/generated_artifacts"
structured_out="$tmp_root/structured-out"
(
  cd "$structured_dir"
  "$haxe_bin" compile.hxml -D rust_codegen_only -D "rust_output=$structured_out"
) >/dev/null
if ! grep -Fq 'serde = { version = "1", features = ["alloc", "derive"], default-features = false }' "$structured_out/Cargo.toml"; then
  echo "error: structured @:rustCargo declarations did not merge deterministically" >&2
  exit 1
fi
for source in native/artifact_helper.rs native_dir/secondary_helper.rs; do
  filename="${source##*/}"
  if ! cmp -s "$structured_dir/$source" "$structured_out/src/$filename"; then
    echo "error: metadata-owned extra source was not copied byte-for-byte: $filename" >&2
    exit 1
  fi
done
for module in artifact_helper secondary_helper; do
  if ! grep -Eq "^(pub )?mod ${module};$" "$structured_out/src/main.rs"; then
    echo "error: metadata-owned extra source module was not included: $module" >&2
    exit 1
  fi
done

conflict_log="$tmp_root/conflict.log"
set +e
(
  cd "$root_dir/test/negative/rust_cargo_structured_conflict"
  "$haxe_bin" compile.hxml -D "rust_output=$tmp_root/conflict-out"
) >"$conflict_log" 2>&1
conflict_status=$?
set -e
if [[ "$conflict_status" -eq 0 ]]; then
  echo "error: conflicting structured @:rustCargo declarations unexpectedly compiled" >&2
  exit 1
fi
if ! grep -q 'Conflicting `@:rustCargo` version for dependency `serde`' "$conflict_log"; then
  echo "error: structured Cargo conflict did not report the owned dependency field" >&2
  exit 1
fi

custom_dir="$root_dir/test/contract/custom_cargo"
custom_out="$tmp_root/custom-out"
(
  cd "$custom_dir"
  "$haxe_bin" \
    -cp . \
    -lib reflaxe.rust \
    -D reflaxe_rust_profile=portable \
    -D rust_codegen_only \
    -D rust_crate=contract_crate \
    -D rust_cargo_toml=Cargo.template.toml \
    -D "rust_output=$custom_out" \
    -main Main
) >/dev/null
if ! cmp -s "$custom_dir/Cargo.expected.toml" "$custom_out/Cargo.toml"; then
  echo "error: custom Cargo ownership/substitution output drifted" >&2
  diff -u "$custom_dir/Cargo.expected.toml" "$custom_out/Cargo.toml" >&2 || true
  exit 1
fi

if [[ "${GENERATED_ARTIFACT_SKIP_CARGO_FAILURE:-0}" != "1" ]]; then
  bash "$root_dir/scripts/ci/check-cargo-failure-propagation.sh"
  echo "[generated-artifact-contract] OK (structured merge/conflict + extra source + custom Cargo + Cargo failure)"
else
  echo "[generated-artifact-contract] OK (structured merge/conflict + extra source + custom Cargo; Cargo failure delegated to adjacent harness stage)"
fi
