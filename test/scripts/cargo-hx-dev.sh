#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
driver="$root_dir/scripts/dev/cargo-hx.sh"
sync_driver="$root_dir/scripts/dev/sync-template-dev-tools.js"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/cargo-hx-dev-test.XXXXXX")"
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  echo "[cargo-hx-dev-test] error: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -F -- "$expected" "$file" >/dev/null || fail "expected '$expected' in $file"
}

app_dir="$tmp_root/app"
bin_dir="$tmp_root/bin"
mkdir -p "$app_dir/src" "$app_dir/out" "$bin_dir"
app_dir="$(cd "$app_dir" && pwd)"

cat > "$app_dir/compile.hxml" <<'HXML'
-cp src
-main Main
-D rust_output=out
HXML

cat > "$app_dir/compile.portable.hxml" <<'HXML'
-cp src
-main Main
-D rust_output=out
-D rust_profile=portable
HXML

cat > "$app_dir/out/Cargo.toml" <<'TOML'
[package]
name = "cargo-hx-dev-fixture"
version = "0.0.0"
edition = "2021"
TOML

haxe_log="$tmp_root/haxe.log"
cargo_log="$tmp_root/cargo.log"

cat > "$bin_dir/haxe" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\n' "$PWD" "$*" >> "$FAKE_HAXE_LOG"
SH

cat > "$bin_dir/cargo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\n' "$PWD" "$*" >> "$FAKE_CARGO_LOG"
SH

chmod +x "$bin_dir/haxe" "$bin_dir/cargo"

run_driver() {
  FAKE_HAXE_LOG="$haxe_log" \
    FAKE_CARGO_LOG="$cargo_log" \
    bash "$driver" "$@" \
      --project "$app_dir" \
      --haxe-bin "$bin_dir/haxe" \
      --cargo-bin "$bin_dir/cargo"
}

: > "$haxe_log"
: > "$cargo_log"
run_driver dev --profile portable --once --no-haxe-server >/dev/null
assert_contains "$haxe_log" "$app_dir|compile.portable.hxml -D rust_no_build"
assert_contains "$cargo_log" "$app_dir/out|run -q"

: > "$haxe_log"
: > "$cargo_log"
run_driver dev --mode test --once --no-haxe-server >/dev/null
assert_contains "$haxe_log" "$app_dir|compile.hxml -D rust_no_build"
assert_contains "$cargo_log" "$app_dir/out|test -q"

: > "$haxe_log"
: > "$cargo_log"
run_driver dev --mode build --once --no-haxe-server >/dev/null
assert_contains "$haxe_log" "-D rust_cargo_subcommand=build"
[[ ! -s "$cargo_log" ]] || fail "dev build mode must let Haxe run the selected Cargo build once"

: > "$haxe_log"
: > "$cargo_log"
run_driver test >/dev/null
assert_contains "$haxe_log" "$app_dir|compile.hxml -D rust_no_build"
assert_contains "$cargo_log" "$app_dir/out|test -q"

if run_driver dev --release --once --no-haxe-server >/dev/null 2>&1; then
  fail "dev mode must reject --release because it is an incremental debug loop"
fi

bash "$driver" --help | grep -F "cargo hx dev" >/dev/null ||
  fail "help must advertise the short project-local dev command"

node "$sync_driver" --check

echo "[cargo-hx-dev-test] ok"
