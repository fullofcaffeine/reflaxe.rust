#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
watch_script="$root_dir/scripts/dev/watch-haxe-rust.sh"

fail() {
  echo "error: $*" >&2
  exit 1
}

assert_regex() {
  local file="$1"
  local pattern="$2"
  local label
  label="$(basename "$file")"
  if ! grep -Eq "$pattern" "$file"; then
    echo "assertion failed: expected pattern '$pattern' in $label" >&2
    echo "--- $label ---" >&2
    cat "$file" >&2 || true
    fail "pattern missing"
  fi
}

assert_not_regex() {
  local file="$1"
  local pattern="$2"
  local label
  label="$(basename "$file")"
  if grep -Eq "$pattern" "$file"; then
    echo "assertion failed: unexpected pattern '$pattern' in $label" >&2
    echo "--- $label ---" >&2
    cat "$file" >&2 || true
    fail "pattern should be absent"
  fi
}

count_regex() {
  local file="$1"
  local pattern="$2"
  grep -Ec "$pattern" "$file" || true
}

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/watch-haxe-rust-test.XXXXXX")"

cleanup() {
  rm -rf "$tmp_root"
}

trap cleanup EXIT INT TERM

fixture_dir="$tmp_root/fixture"
bin_dir="$tmp_root/bin"
haxe_log="$tmp_root/haxe.log"
watchexec_log="$tmp_root/watchexec.log"
wait_pid_file="$tmp_root/haxe_wait_pid.txt"
wait_port_file="$tmp_root/haxe_wait_port.txt"
connect_fail_flag_file="$tmp_root/connect_fail_once.flag"

mkdir -p "$fixture_dir/src" "$bin_dir"

cat > "$fixture_dir/compile.hxml" <<'EOF'
-cp src
-main Main
-D rust_output=out
-D rust_no_build
EOF

cat > "$fixture_dir/src/Main.hx" <<'EOF'
class Main {
  static function main() {}
}
EOF

cat > "$bin_dir/haxe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${FAKE_HAXE_LOG:?}"
printf '%s\n' "$*" >> "$log_file"

if [[ "${1:-}" == "--wait" ]]; then
  printf '%s\n' "${2:-}" > "${FAKE_HAXE_WAIT_PORT_FILE:?}"
  printf '%s\n' "$$" > "${FAKE_HAXE_WAIT_PID_FILE:?}"
  trap 'exit 0' TERM INT
  while true; do
    sleep 1
  done
fi

if [[ "${1:-}" == "--connect" ]]; then
  shift
  port="${1:-}"
  shift || true

  if [[ "${1:-}" == "-version" ]]; then
    echo "4.3.7"
    exit 0
  fi

  if [[ "${FAKE_HAXE_CONNECT_ALWAYS_FAIL:-0}" == "1" ]]; then
    exit 1
  fi

  if [[ "${FAKE_HAXE_CONNECT_FAIL_FIRST:-0}" == "1" ]]; then
    flag_file="${FAKE_HAXE_CONNECT_FAIL_FLAG_FILE:?}"
    if [[ ! -f "$flag_file" ]]; then
      : > "$flag_file"
      exit 1
    fi
  fi

  hxml_file="${1:-}"
  out_dir="$(dirname "$hxml_file")/out"
  mkdir -p "$out_dir"
  touch "$out_dir/Cargo.toml"
  exit 0
fi

hxml_file="${1:-}"
out_dir="$(dirname "$hxml_file")/out"
mkdir -p "$out_dir"
touch "$out_dir/Cargo.toml"
EOF

cat > "$bin_dir/watchexec" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log_file="${FAKE_WATCHEXEC_LOG:?}"
printf '%s\n' "$*" >> "$log_file"

declare -a command=()
seen_separator=0
for arg in "$@"; do
  if [[ "$seen_separator" -eq 1 ]]; then
    command+=("$arg")
    continue
  fi
  if [[ "$arg" == "--" ]]; then
    seen_separator=1
  fi
done

if [[ "$seen_separator" -eq 0 || "${#command[@]}" -eq 0 ]]; then
  echo "fake watchexec: expected command after --" >&2
  exit 2
fi

"${command[@]}"
EOF

chmod +x "$bin_dir/haxe" "$bin_dir/watchexec"

reset_logs() {
  : > "$haxe_log"
  : > "$watchexec_log"
  rm -f "$wait_pid_file" "$wait_port_file" "$connect_fail_flag_file"
}

run_watch() {
  PATH="$bin_dir:$PATH" \
  FAKE_HAXE_LOG="$haxe_log" \
  FAKE_HAXE_WAIT_PID_FILE="$wait_pid_file" \
  FAKE_HAXE_WAIT_PORT_FILE="$wait_port_file" \
  FAKE_HAXE_CONNECT_FAIL_FLAG_FILE="$connect_fail_flag_file" \
  FAKE_WATCHEXEC_LOG="$watchexec_log" \
  bash "$watch_script" --hxml "$fixture_dir/compile.hxml" --mode build --haxe-bin "$bin_dir/haxe" "$@"
}

reset_logs
run_watch >/dev/null 2>&1
assert_regex "$haxe_log" '^--wait [0-9]+$'
assert_regex "$haxe_log" '^--connect [0-9]+ -version$'
assert_regex "$haxe_log" '^--connect [0-9]+ compile\.hxml$'
if [[ ! -f "$wait_pid_file" ]]; then
  fail "expected watcher-owned haxe --wait pid file"
fi
wait_pid="$(cat "$wait_pid_file")"
if kill -0 "$wait_pid" >/dev/null 2>&1; then
  fail "watcher-owned haxe --wait process should be cleaned up"
fi

reset_logs
run_watch --no-haxe-server >/dev/null 2>&1
assert_not_regex "$haxe_log" '^--wait '
assert_not_regex "$haxe_log" '^--connect '
assert_regex "$haxe_log" '^compile\.hxml$'

reset_logs
run_watch --once >/dev/null 2>&1
assert_not_regex "$haxe_log" '^--wait '
assert_not_regex "$haxe_log" '^--connect '
assert_regex "$haxe_log" '^compile\.hxml$'

reset_logs
PATH="$bin_dir:$PATH" \
FAKE_HAXE_LOG="$haxe_log" \
FAKE_HAXE_WAIT_PID_FILE="$wait_pid_file" \
FAKE_HAXE_WAIT_PORT_FILE="$wait_port_file" \
FAKE_HAXE_CONNECT_FAIL_FLAG_FILE="$connect_fail_flag_file" \
FAKE_HAXE_CONNECT_FAIL_FIRST=1 \
bash "$watch_script" --once --hxml "$fixture_dir/compile.hxml" --mode build --haxe-bin "$bin_dir/haxe" --haxe-server-port 6111 >/dev/null 2>&1
connect_attempts="$(count_regex "$haxe_log" '^--connect 6111 compile\.hxml$')"
if [[ "$connect_attempts" -ne 2 ]]; then
  fail "expected 2 connect compile attempts after single transient failure, got $connect_attempts"
fi
assert_not_regex "$haxe_log" '^compile\.hxml$'

reset_logs
PATH="$bin_dir:$PATH" \
FAKE_HAXE_LOG="$haxe_log" \
FAKE_HAXE_WAIT_PID_FILE="$wait_pid_file" \
FAKE_HAXE_WAIT_PORT_FILE="$wait_port_file" \
FAKE_HAXE_CONNECT_FAIL_FLAG_FILE="$connect_fail_flag_file" \
FAKE_HAXE_CONNECT_ALWAYS_FAIL=1 \
bash "$watch_script" --once --hxml "$fixture_dir/compile.hxml" --mode build --haxe-bin "$bin_dir/haxe" --haxe-server-port 6111 >/dev/null 2>&1
connect_attempts="$(count_regex "$haxe_log" '^--connect 6111 compile\.hxml$')"
if [[ "$connect_attempts" -ne 2 ]]; then
  fail "expected 2 connect compile attempts before direct fallback, got $connect_attempts"
fi
assert_regex "$haxe_log" '^compile\.hxml$'

echo "[watcher-test] ok"
