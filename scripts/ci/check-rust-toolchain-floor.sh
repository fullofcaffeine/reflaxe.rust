#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
policy_script="$root_dir/scripts/ci/rust-toolchain-policy.js"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-rust-toolchain-floor.XXXXXX")"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

minimum="$(node "$policy_script" --print minimum)"
actual="$(rustc --version | sed -n 's/^rustc \([^ ]*\).*/\1/p')"

if ! node "$policy_script" --assert-supported "$actual"; then
  exit 1
fi

if [[ "${RUST_TOOLCHAIN_EXPECT_MINIMUM:-0}" == "1" && "$actual" != "$minimum" ]]; then
  echo "[rust-toolchain-floor] ERROR: minimum-lane CI resolved rustc $actual; expected exact baseline $minimum." >&2
  exit 1
fi

haxe_bin="${HAXE_BIN:-}"
if [[ -z "$haxe_bin" ]]; then
  if [[ -x "$root_dir/node_modules/.bin/haxe" ]]; then
    haxe_bin="$root_dir/node_modules/.bin/haxe"
  else
    haxe_bin="haxe"
  fi
fi

out_dir="$tmp_root/generated"
(cd "$root_dir/test/snapshot/v1_smoke" && "$haxe_bin" compile.hxml -D rust_no_build -D "rust_output=$out_dir")

for manifest in "$out_dir/Cargo.toml" "$out_dir/hxrt/Cargo.toml"; do
  if ! grep -Fxq "rust-version = \"$minimum\"" "$manifest"; then
    echo "[rust-toolchain-floor] ERROR: generated manifest does not declare rust-version $minimum: $manifest" >&2
    exit 1
  fi
done

if [[ "$actual" == "$minimum" ]]; then
  unsupported="$(node -e 'const m=/^([0-9]+)\.([0-9]+)\.([0-9]+)$/.exec(process.argv[1]); console.log(`${m[1]}.${BigInt(m[2]) + 1n}.0`)' "$minimum")"
  probe="$tmp_root/unsupported-probe"
  mkdir -p "$probe/src"
  printf 'fn main() {}\n' > "$probe/src/main.rs"
  printf '[package]\nname = "unsupported_floor_probe"\nversion = "0.1.0"\nedition = "2021"\nrust-version = "%s"\n' "$unsupported" > "$probe/Cargo.toml"

  set +e
  cargo check --manifest-path "$probe/Cargo.toml" > "$probe/cargo.log" 2>&1
  cargo_status=$?
  set -e
  if [[ "$cargo_status" -eq 0 ]]; then
    echo "[rust-toolchain-floor] ERROR: Cargo accepted a manifest requiring unsupported rustc $unsupported on rustc $actual." >&2
    exit 1
  fi
  if ! grep -Fq "requires rustc $unsupported" "$probe/cargo.log"; then
    echo "[rust-toolchain-floor] ERROR: Cargo rejection did not provide the expected required-version guidance." >&2
    sed -n '1,120p' "$probe/cargo.log" >&2
    exit 1
  fi
fi

echo "[rust-toolchain-floor] OK (minimum=$minimum actual=$actual generated Cargo metadata enforced)"
