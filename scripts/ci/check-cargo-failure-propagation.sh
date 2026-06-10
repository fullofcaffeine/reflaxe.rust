#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/reflaxe-rust-cargo-failure.XXXXXX")"

cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

cat > "$tmp_root/Main.hx" <<'HX'
class Main {
  static function main() {
    trace("cargo failure propagation");
  }
}
HX

cat > "$tmp_root/compile.hxml" <<'HXML'
-cp .
-lib reflaxe.rust
-D reflaxe_rust_profile=portable
-D rust_output=out
-D rust_cargo_subcommand=definitely-not-a-cargo-subcommand
-main Main
HXML

log_file="$tmp_root/haxe.log"
set +e
(
  cd "$tmp_root"
  haxe compile.hxml
) >"$log_file" 2>&1
code=$?
set -e

if [[ "$code" -eq 0 ]]; then
  echo "error: haxe exited successfully even though configured Cargo invocation failed" >&2
  sed -n '1,160p' "$log_file" >&2
  exit 1
fi

if ! grep -q "definitely-not-a-cargo-subcommand" "$log_file"; then
  echo "error: expected Cargo failure log to mention the invalid subcommand" >&2
  sed -n '1,160p' "$log_file" >&2
  exit 1
fi

printf '[cargo-failure-propagation] ok (haxe exit %s)\n' "$code"
