#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
invocation_dir="$(pwd)"
cd "$root_dir"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/ci/perf-hxrt-overhead.sh [options]

Options:
  --update-baseline         Regenerate scripts/ci/perf/hxrt-baseline.json from current metrics.
  --keep-work               Keep build work directory under .cache/perf-hxrt/work.
  -h, --help                Show this help.

Environment:
  HAXE_BIN                  Haxe binary (default: haxe)
  CARGO_BIN                 Cargo binary (default: cargo)
  HXRT_PERF_CACHE_DIR       Cache/output root (default: .cache/perf-hxrt)
  HXRT_PERF_BASELINE_FILE   Baseline JSON path (default: scripts/ci/perf/hxrt-baseline.json)
  HXRT_PERF_SIZE_WARN_PCT   Soft warning threshold for size ratios (default: 5)
  HXRT_PERF_RUNTIME_WARN_PCT Soft warning threshold for runtime ratios (default: 10)
  HXRT_PERF_HELLO_ITERS     Startup loop count for hello case (default: 300)
  HXRT_PERF_ARRAY_ITERS     Startup loop count for array case (default: 300)
  HXRT_PERF_HOT_LOOP_ITERS  Startup loop count for hot_loop case (default: 300)
  HXRT_PERF_HOT_LOOP_INPROC_RUNS In-process sample count for hot_loop_inproc binaries (default: 20)
  HXRT_PERF_CHAT_ITERS      Startup loop count for chat headless case (default: 40)
USAGE
}

log() {
  printf '[hxrt-perf] %s\n' "$*"
}

fail() {
  printf '[hxrt-perf] error: %s\n' "$*" >&2
  exit 2
}

display_path() {
  local input="$1"
  if [[ "$input" == "$invocation_dir" ]]; then
    printf ".\n"
  elif [[ "$input" == "$invocation_dir/"* ]]; then
    printf ".%s\n" "${input#"$invocation_dir"}"
  elif [[ "$input" == "$root_dir" ]]; then
    printf ".\n"
  elif [[ "$input" == "$root_dir/"* ]]; then
    printf "%s\n" "${input#"$root_dir/"}"
  else
    printf "[external:%s]\n" "$(basename "$input")"
  fi
}

is_truthy() {
  local value="${1:-}"
  case "$value" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "required command not found: $cmd"
  fi
}

filesize_bytes() {
  local file="$1"
  if stat -f%z "$file" >/dev/null 2>&1; then
    stat -f%z "$file"
  else
    stat -c%s "$file"
  fi
}

stripped_size_bytes() {
  local file="$1"
  local tmp="${file}.hxrt-perf-strip.tmp"
  cp "$file" "$tmp"
  if strip -x "$tmp" >/dev/null 2>&1; then
    :
  elif strip --strip-unneeded "$tmp" >/dev/null 2>&1; then
    :
  elif strip "$tmp" >/dev/null 2>&1; then
    :
  fi
  local out
  out="$(filesize_bytes "$tmp")"
  rm -f "$tmp"
  printf "%s\n" "$out"
}

extract_package_name() {
  local cargo_toml="$1"
  awk -F'=' '
    function trim(v) {
      sub(/^[ \t]+/, "", v)
      sub(/[ \t]+$/, "", v)
      return v
    }
    /^\[package\]/ { in_package = 1; next }
    /^\[/ {
      if (in_package == 1) {
        exit
      }
    }
    in_package == 1 && $1 ~ /^[ \t]*name[ \t]*$/ {
      value = trim($2)
      gsub(/"/, "", value)
      print value
      exit
    }
  ' "$cargo_toml"
}

measure_startup_ms() {
  local bin="$1"
  local iterations="$2"
  local timing_log="$3"

  ITER="$iterations" BIN="$bin" "$time_bin" -p bash -c '
    i=0
    while [ "$i" -lt "$ITER" ]; do
      "$BIN" >/dev/null 2>&1 || exit 1
      i=$((i + 1))
    done
  ' >/dev/null 2>"$timing_log"

  local real_seconds
  real_seconds="$(awk '/^real[[:space:]]+/ { print $2; exit }' "$timing_log")"
  if [[ -z "${real_seconds:-}" ]]; then
    fail "failed to parse startup timing from $(display_path "$timing_log")"
  fi

  awk -v real="$real_seconds" -v count="$iterations" 'BEGIN { printf "%.6f\n", (real * 1000.0) / count }'
}

measure_inprocess_ms() {
  local bin="$1"
  local sample_count="$2"
  local timing_log="$3"
  HXRT_PERF_BIN="$bin" HXRT_PERF_RUNS="$sample_count" node <<'NODE' > "$timing_log"
const { spawnSync } = require("child_process");

const bin = process.env.HXRT_PERF_BIN || "";
const runs = Number(process.env.HXRT_PERF_RUNS || "0");
if (!bin || !Number.isFinite(runs) || runs <= 0) {
  console.error("invalid in-process timing inputs");
  process.exit(2);
}

const startedNs = process.hrtime.bigint();
for (let i = 0; i < runs; i += 1) {
  const runResult = spawnSync(bin, [], { stdio: "ignore" });
  if (runResult.error) {
    console.error(runResult.error.message);
    process.exit(1);
  }
  if (runResult.status !== 0) {
    process.exit(runResult.status || 1);
  }
}
const elapsedNs = Number(process.hrtime.bigint() - startedNs);
const avgMs = elapsedNs / 1e6 / runs;
process.stdout.write(`${avgMs.toFixed(6)}\n`);
NODE

  local runtime_avg_ms
  runtime_avg_ms="$(tr -d '\r' < "$timing_log" | tail -n 1)"
  if [[ -z "${runtime_avg_ms:-}" ]]; then
    fail "failed to parse in-process timing from $(display_path "$timing_log")"
  fi
  printf "%s\n" "$runtime_avg_ms"
}

write_pure_hello_crate() {
  local crate_dir="$1"
  mkdir -p "$crate_dir/src"
  cat > "$crate_dir/Cargo.toml" <<'EOF'
[package]
name = "pure_hello"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF
  cat > "$crate_dir/src/main.rs" <<'EOF'
fn main() {
    println!("hi");
}
EOF
}

write_pure_array_crate() {
  local crate_dir="$1"
  mkdir -p "$crate_dir/src"
  cat > "$crate_dir/Cargo.toml" <<'EOF'
[package]
name = "pure_array"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF
  cat > "$crate_dir/src/main.rs" <<'EOF'
fn main() {
    let xs = [1, 2, 3];
    let mut sum = 0;
    for x in xs {
        sum += x;
    }
    println!("{}", sum);
}
EOF
}

write_pure_hot_loop_crate() {
  local crate_dir="$1"
  mkdir -p "$crate_dir/src"
  cat > "$crate_dir/Cargo.toml" <<'EOF'
[package]
name = "pure_hot_loop"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF
  cat > "$crate_dir/src/main.rs" <<'EOF'
fn main() {
    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);
    let seed = (millis as i32) & 0xFFFF;
    let mut acc = seed;
    let mut i: i32 = 0;
    while i < 4_000_000 {
        acc = (acc + (((i * 31) ^ (i >> 3)) & 0x7FFF_FFFF)) & 0x7FFF_FFFF;
        i += 1;
    }
    if acc == seed - 1 {
        println!("unreachable");
    }
}
EOF
}

write_pure_hot_loop_inproc_crate() {
  local crate_dir="$1"
  mkdir -p "$crate_dir/src"
  cat > "$crate_dir/Cargo.toml" <<'EOF'
[package]
name = "pure_hot_loop_inproc"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF
  cat > "$crate_dir/src/main.rs" <<'EOF'
fn crunch(mut acc: i32, n: i32) -> i32 {
    let mut i: i32 = 0;
    while i < n {
        acc = acc + ((i * 31 ^ (i as u32 >> 3) as i32) & 0x7fff_ffff) & 0x7fff_ffff;
        i += 1;
    }
    acc
}

fn main() {
    const INNER_ITERS: i32 = 4_000_000;
    const OUTER_RUNS: i32 = 24;

    let millis = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);

    let seed = (millis as i32) & 0xffff;
    let mut acc = crunch(seed, 1_024);

    let mut run: i32 = 0;
    while run < OUTER_RUNS {
        acc = crunch((acc + run) & 0x7fff_ffff, INNER_ITERS);
        run += 1;
    }

    if acc == -1 {
        println!("unreachable");
    }

}
EOF
}
update_baseline=0
keep_work=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-baseline)
      update_baseline=1
      shift
      ;;
    --keep-work)
      keep_work=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

haxe_bin="${HAXE_BIN:-haxe}"
cargo_bin="${CARGO_BIN:-cargo}"
cache_root="${HXRT_PERF_CACHE_DIR:-$root_dir/.cache/perf-hxrt}"
baseline_file="${HXRT_PERF_BASELINE_FILE:-$root_dir/scripts/ci/perf/hxrt-baseline.json}"
baseline_display="$(display_path "$baseline_file")"
size_warn_pct="${HXRT_PERF_SIZE_WARN_PCT:-5}"
runtime_warn_pct="${HXRT_PERF_RUNTIME_WARN_PCT:-10}"
hello_iters="${HXRT_PERF_HELLO_ITERS:-300}"
array_iters="${HXRT_PERF_ARRAY_ITERS:-300}"
hot_loop_iters="${HXRT_PERF_HOT_LOOP_ITERS:-300}"
hot_loop_inproc_runs="${HXRT_PERF_HOT_LOOP_INPROC_RUNS:-20}"
chat_iters="${HXRT_PERF_CHAT_ITERS:-40}"

if [[ -x /usr/bin/time ]]; then
  time_bin="/usr/bin/time"
else
  fail "required timing command not found: /usr/bin/time"
fi

require_command "$haxe_bin"
require_command "$cargo_bin"
require_command node

work_dir="$cache_root/work"
results_dir="$cache_root/results"
metrics_tsv="$results_dir/raw_metrics.tsv"
current_json="$results_dir/current.json"
comparison_json="$results_dir/comparison.json"
summary_md="$results_dir/summary.md"
warnings_txt="$results_dir/warnings.txt"

cleanup() {
  local original_exit="${1:-0}"
  if [[ "$keep_work" -eq 1 ]] || is_truthy "${KEEP_ARTIFACTS:-0}"; then
    log "keeping work dir: $(display_path "$work_dir")"
    return "$original_exit"
  fi
  rm -rf "$work_dir"
  return "$original_exit"
}

trap 'cleanup $?' EXIT

rm -rf "$work_dir"
mkdir -p "$work_dir" "$results_dir"
mkdir -p "$(dirname "$baseline_file")"

printf "id\tcase\tprofile\tkind\tbinary_bytes\tstripped_bytes\truntime_mode\truntime_avg_ms\truntime_iterations\n" > "$metrics_tsv"

log "collecting metrics (results: $(display_path "$results_dir"))"

declare -a profiles=(portable idiomatic rusty metal)

record_metric_row() {
  local id="$1"
  local case_name="$2"
  local profile="$3"
  local kind="$4"
  local bin_path="$5"
  local runtime_mode="$6"
  local runtime_avg_ms="$7"
  local runtime_iterations="$8"

  if [[ ! -f "$bin_path" ]]; then
    fail "binary not found: $(display_path "$bin_path")"
  fi

  local bin_bytes
  bin_bytes="$(filesize_bytes "$bin_path")"
  local stripped_bytes
  stripped_bytes="$(stripped_size_bytes "$bin_path")"

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$id" "$case_name" "$profile" "$kind" \
    "$bin_bytes" "$stripped_bytes" \
    "$runtime_mode" "$runtime_avg_ms" "$runtime_iterations" >> "$metrics_tsv"
}

record_metric_startup() {
  local id="$1"
  local case_name="$2"
  local profile="$3"
  local kind="$4"
  local bin_path="$5"
  local iterations="$6"
  local startup_log="$7"

  local runtime_avg_ms
  runtime_avg_ms="$(measure_startup_ms "$bin_path" "$iterations" "$startup_log")"
  record_metric_row "$id" "$case_name" "$profile" "$kind" "$bin_path" "startup" "$runtime_avg_ms" "$iterations"
}

record_metric_inproc() {
  local id="$1"
  local case_name="$2"
  local profile="$3"
  local kind="$4"
  local bin_path="$5"
  local run_count="$6"
  local output_log="$7"

  local runtime_avg_ms
  runtime_avg_ms="$(measure_inprocess_ms "$bin_path" "$run_count" "$output_log")"
  record_metric_row "$id" "$case_name" "$profile" "$kind" "$bin_path" "inproc" "$runtime_avg_ms" "$run_count"
}

for profile in "${profiles[@]}"; do
  log "hello case ($profile)"
  case_dir="$work_dir/hello/$profile"
  out_dir="$case_dir/out"
  target_dir="$case_dir/target"
  mkdir -p "$case_dir"
  "$haxe_bin" -cp "$root_dir/examples/hello" -lib reflaxe.rust \
    -D reflaxe_rust_strict_examples \
    -D "reflaxe_rust_profile=$profile" \
    -D "rust_output=$out_dir" \
    -D rust_no_build \
    -main Main >/dev/null
  CARGO_TARGET_DIR="$target_dir" "$cargo_bin" build --manifest-path "$out_dir/Cargo.toml" --release -q
  package_name="$(extract_package_name "$out_dir/Cargo.toml")"
  [[ -n "$package_name" ]] || fail "unable to parse package name in $(display_path "$out_dir/Cargo.toml")"
  record_metric_startup "hello_haxe_${profile}" "hello" "$profile" "haxe" \
    "$target_dir/release/$package_name" "$hello_iters" "$case_dir/startup.time"
done

log "hello pure rust baseline"
hello_pure_dir="$work_dir/hello/pure"
hello_pure_target="$hello_pure_dir/target"
write_pure_hello_crate "$hello_pure_dir"
CARGO_TARGET_DIR="$hello_pure_target" "$cargo_bin" build --manifest-path "$hello_pure_dir/Cargo.toml" --release -q
record_metric_startup "hello_pure_rust" "hello" "pure" "pure_rust" \
  "$hello_pure_target/release/pure_hello" "$hello_iters" "$hello_pure_dir/startup.time"

for profile in "${profiles[@]}"; do
  log "array case ($profile)"
  case_dir="$work_dir/array/$profile"
  out_dir="$case_dir/out"
  target_dir="$case_dir/target"
  mkdir -p "$case_dir"
  "$haxe_bin" -cp "$root_dir/test/snapshot/for_array" -lib reflaxe.rust \
    -D "reflaxe_rust_profile=$profile" \
    -D "rust_output=$out_dir" \
    -D rust_no_build \
    -main Main >/dev/null
  CARGO_TARGET_DIR="$target_dir" "$cargo_bin" build --manifest-path "$out_dir/Cargo.toml" --release -q
  package_name="$(extract_package_name "$out_dir/Cargo.toml")"
  [[ -n "$package_name" ]] || fail "unable to parse package name in $(display_path "$out_dir/Cargo.toml")"
  record_metric_startup "array_haxe_${profile}" "array" "$profile" "haxe" \
    "$target_dir/release/$package_name" "$array_iters" "$case_dir/startup.time"
done

log "array pure rust baseline"
array_pure_dir="$work_dir/array/pure"
array_pure_target="$array_pure_dir/target"
write_pure_array_crate "$array_pure_dir"
CARGO_TARGET_DIR="$array_pure_target" "$cargo_bin" build --manifest-path "$array_pure_dir/Cargo.toml" --release -q
record_metric_startup "array_pure_rust" "array" "pure" "pure_rust" \
  "$array_pure_target/release/pure_array" "$array_iters" "$array_pure_dir/startup.time"

for profile in "${profiles[@]}"; do
  log "hot_loop case ($profile)"
  case_dir="$work_dir/hot_loop/$profile"
  out_dir="$case_dir/out"
  target_dir="$case_dir/target"
  mkdir -p "$case_dir"
  "$haxe_bin" -cp "$root_dir/test/perf/hot_loop" -lib reflaxe.rust \
    -D "reflaxe_rust_profile=$profile" \
    -D "rust_output=$out_dir" \
    -D rust_no_build \
    -main Main >/dev/null
  CARGO_TARGET_DIR="$target_dir" "$cargo_bin" build --manifest-path "$out_dir/Cargo.toml" --release -q
  package_name="$(extract_package_name "$out_dir/Cargo.toml")"
  [[ -n "$package_name" ]] || fail "unable to parse package name in $(display_path "$out_dir/Cargo.toml")"
  record_metric_startup "hot_loop_haxe_${profile}" "hot_loop" "$profile" "haxe" \
    "$target_dir/release/$package_name" "$hot_loop_iters" "$case_dir/startup.time"
done

log "hot_loop pure rust baseline"
hot_loop_pure_dir="$work_dir/hot_loop/pure"
hot_loop_pure_target="$hot_loop_pure_dir/target"
write_pure_hot_loop_crate "$hot_loop_pure_dir"
CARGO_TARGET_DIR="$hot_loop_pure_target" "$cargo_bin" build --manifest-path "$hot_loop_pure_dir/Cargo.toml" --release -q
record_metric_startup "hot_loop_pure_rust" "hot_loop" "pure" "pure_rust" \
  "$hot_loop_pure_target/release/pure_hot_loop" "$hot_loop_iters" "$hot_loop_pure_dir/startup.time"

for profile in "${profiles[@]}"; do
  log "hot_loop_inproc case ($profile)"
  case_dir="$work_dir/hot_loop_inproc/$profile"
  out_dir="$case_dir/out"
  target_dir="$case_dir/target"
  mkdir -p "$case_dir"
  "$haxe_bin" -cp "$root_dir/test/perf/hot_loop_inproc" -lib reflaxe.rust \
    -D "reflaxe_rust_profile=$profile" \
    -D "rust_output=$out_dir" \
    -D rust_no_build \
    -main Main >/dev/null
  CARGO_TARGET_DIR="$target_dir" "$cargo_bin" build --manifest-path "$out_dir/Cargo.toml" --release -q
  package_name="$(extract_package_name "$out_dir/Cargo.toml")"
  [[ -n "$package_name" ]] || fail "unable to parse package name in $(display_path "$out_dir/Cargo.toml")"
  record_metric_inproc "hot_loop_inproc_haxe_${profile}" "hot_loop_inproc" "$profile" "haxe" \
    "$target_dir/release/$package_name" "$hot_loop_inproc_runs" "$case_dir/inproc.out"
done

log "hot_loop_inproc pure rust baseline"
hot_loop_inproc_pure_dir="$work_dir/hot_loop_inproc/pure"
hot_loop_inproc_pure_target="$hot_loop_inproc_pure_dir/target"
write_pure_hot_loop_inproc_crate "$hot_loop_inproc_pure_dir"
CARGO_TARGET_DIR="$hot_loop_inproc_pure_target" "$cargo_bin" build --manifest-path "$hot_loop_inproc_pure_dir/Cargo.toml" --release -q
record_metric_inproc "hot_loop_inproc_pure_rust" "hot_loop_inproc" "pure" "pure_rust" \
  "$hot_loop_inproc_pure_target/release/pure_hot_loop_inproc" "$hot_loop_inproc_runs" "$hot_loop_inproc_pure_dir/inproc.out"

for profile in "${profiles[@]}"; do
  log "chat case ($profile)"
  case_dir="$work_dir/chat/$profile"
  out_dir="$case_dir/out"
  target_dir="$case_dir/target"
  mkdir -p "$case_dir"
  (
    cd "$root_dir/examples/chat_loopback"
    "$haxe_bin" "compile.${profile}.ci.hxml" \
      -D "rust_output=$out_dir" \
      -D rust_no_build >/dev/null
  )
  CARGO_TARGET_DIR="$target_dir" "$cargo_bin" build --manifest-path "$out_dir/Cargo.toml" --release -q
  package_name="$(extract_package_name "$out_dir/Cargo.toml")"
  [[ -n "$package_name" ]] || fail "unable to parse package name in $(display_path "$out_dir/Cargo.toml")"
  record_metric_startup "chat_haxe_${profile}" "chat" "$profile" "haxe" \
    "$target_dir/release/$package_name" "$chat_iters" "$case_dir/startup.time"
done

haxe_version="$("$haxe_bin" -version 2>/dev/null | tr -d '\r' | head -n 1 || true)"
rustc_version="$(rustc --version 2>/dev/null | tr -d '\r' | head -n 1 || true)"

HXRT_PERF_METRICS_TSV="$metrics_tsv" \
HXRT_PERF_CURRENT_JSON="$current_json" \
HXRT_PERF_COMPARISON_JSON="$comparison_json" \
HXRT_PERF_SUMMARY_MD="$summary_md" \
HXRT_PERF_WARNINGS_TXT="$warnings_txt" \
HXRT_PERF_BASELINE_FILE="$baseline_file" \
HXRT_PERF_BASELINE_DISPLAY="$baseline_display" \
HXRT_PERF_UPDATE_BASELINE="$update_baseline" \
HXRT_PERF_SIZE_WARN_PCT="$size_warn_pct" \
HXRT_PERF_RUNTIME_WARN_PCT="$runtime_warn_pct" \
HXRT_PERF_HELLO_ITERS="$hello_iters" \
HXRT_PERF_ARRAY_ITERS="$array_iters" \
HXRT_PERF_HOT_LOOP_ITERS="$hot_loop_iters" \
HXRT_PERF_HOT_LOOP_INPROC_RUNS="$hot_loop_inproc_runs" \
HXRT_PERF_CHAT_ITERS="$chat_iters" \
HXRT_PERF_HAXE_VERSION="$haxe_version" \
HXRT_PERF_RUSTC_VERSION="$rustc_version" \
node <<'NODE'
const fs = require("fs");
const path = require("path");

const metricsPath = process.env.HXRT_PERF_METRICS_TSV;
const currentJsonPath = process.env.HXRT_PERF_CURRENT_JSON;
const comparisonJsonPath = process.env.HXRT_PERF_COMPARISON_JSON;
const summaryPath = process.env.HXRT_PERF_SUMMARY_MD;
const warningsPath = process.env.HXRT_PERF_WARNINGS_TXT;
const baselinePath = process.env.HXRT_PERF_BASELINE_FILE;
const baselineDisplay = process.env.HXRT_PERF_BASELINE_DISPLAY || baselinePath;
const updateBaseline = process.env.HXRT_PERF_UPDATE_BASELINE === "1";
const sizeWarnPct = Number(process.env.HXRT_PERF_SIZE_WARN_PCT || "5");
const runtimeWarnPct = Number(process.env.HXRT_PERF_RUNTIME_WARN_PCT || "10");
const helloIters = Number(process.env.HXRT_PERF_HELLO_ITERS || "300");
const arrayIters = Number(process.env.HXRT_PERF_ARRAY_ITERS || "300");
const hotLoopIters = Number(process.env.HXRT_PERF_HOT_LOOP_ITERS || "300");
const hotLoopInprocRuns = Number(process.env.HXRT_PERF_HOT_LOOP_INPROC_RUNS || "20");
const chatIters = Number(process.env.HXRT_PERF_CHAT_ITERS || "40");
const haxeVersion = process.env.HXRT_PERF_HAXE_VERSION || "";
const rustcVersion = process.env.HXRT_PERF_RUSTC_VERSION || "";

const profiles = ["portable", "idiomatic", "rusty", "metal"];

function parseMetrics(tsvPath) {
  const raw = fs.readFileSync(tsvPath, "utf8").trim();
  const lines = raw.split(/\r?\n/);
  const header = lines.shift();
  const cols = header.split("\t");
  return lines
    .filter((line) => line.trim().length > 0)
    .map((line) => {
      const fields = line.split("\t");
      const entry = {};
      cols.forEach((col, index) => {
        entry[col] = fields[index] ?? "";
      });
      return {
        id: entry.id,
        case: entry.case,
        profile: entry.profile,
        kind: entry.kind,
        binary_bytes: Number(entry.binary_bytes),
        stripped_bytes: Number(entry.stripped_bytes),
        runtime_mode: entry.runtime_mode,
        runtime_avg_ms: Number(entry.runtime_avg_ms),
        runtime_iterations: Number(entry.runtime_iterations),
      };
    });
}

const metrics = parseMetrics(metricsPath);
const byId = Object.fromEntries(metrics.map((metric) => [metric.id, metric]));

function requireMetric(id) {
  const found = byId[id];
  if (!found) {
    throw new Error(`Missing metric: ${id}`);
  }
  return found;
}

function ratio(current, base) {
  if (base === 0) {
    return 0;
  }
  return current / base;
}

function buildCaseOverhead(caseName) {
  const pure = requireMetric(`${caseName}_pure_rust`);
  const out = {};
  for (const profile of profiles) {
    const metric = requireMetric(`${caseName}_haxe_${profile}`);
    out[profile] = {
      binaryRatio: ratio(metric.binary_bytes, pure.binary_bytes),
      strippedRatio: ratio(metric.stripped_bytes, pure.stripped_bytes),
      runtimeRatio: ratio(metric.runtime_avg_ms, pure.runtime_avg_ms),
    };
  }
  return out;
}

const helloOverheadRatios = buildCaseOverhead("hello");
const arrayOverheadRatios = buildCaseOverhead("array");
const hotLoopOverheadRatios = buildCaseOverhead("hot_loop");
const hotLoopInprocOverheadRatios = buildCaseOverhead("hot_loop_inproc");

const chatMetrics = Object.fromEntries(
  profiles.map((profile) => [profile, requireMetric(`chat_haxe_${profile}`)])
);
const chatMin = {
  binary_bytes: Math.min(...profiles.map((profile) => chatMetrics[profile].binary_bytes)),
  stripped_bytes: Math.min(...profiles.map((profile) => chatMetrics[profile].stripped_bytes)),
  runtime_avg_ms: Math.min(...profiles.map((profile) => chatMetrics[profile].runtime_avg_ms)),
};
const chatRelativeToMin = {};
for (const profile of profiles) {
  const metric = chatMetrics[profile];
  chatRelativeToMin[profile] = {
    binaryRatio: ratio(metric.binary_bytes, chatMin.binary_bytes),
    strippedRatio: ratio(metric.stripped_bytes, chatMin.stripped_bytes),
    runtimeRatio: ratio(metric.runtime_avg_ms, chatMin.runtime_avg_ms),
  };
}

const current = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  toolchain: {
    haxe: haxeVersion,
    rustc: rustcVersion,
  },
  thresholds: {
    sizeWarnPct,
    runtimeWarnPct,
  },
  runtimeLoops: {
    hello: helloIters,
    array: arrayIters,
    hot_loop: hotLoopIters,
    hot_loop_inproc: hotLoopInprocRuns,
    chat: chatIters,
  },
  metrics,
  derived: {
    helloOverheadRatios,
    arrayOverheadRatios,
    hotLoopOverheadRatios,
    hotLoopInprocOverheadRatios,
    chatRelativeToMin,
  },
};

fs.mkdirSync(path.dirname(currentJsonPath), { recursive: true });
fs.writeFileSync(currentJsonPath, `${JSON.stringify(current, null, 2)}\n`);

const baselinePayload = {
  schemaVersion: 1,
  generatedAt: current.generatedAt,
  thresholds: current.thresholds,
  runtimeLoops: current.runtimeLoops,
  derivedBaseline: current.derived,
};

if (updateBaseline) {
  fs.mkdirSync(path.dirname(baselinePath), { recursive: true });
  fs.writeFileSync(baselinePath, `${JSON.stringify(baselinePayload, null, 2)}\n`);
}

const warnings = [];

function compareGroup(groupLabel, currentGroup, baselineGroup, opts) {
  if (!baselineGroup) {
    warnings.push(`${groupLabel}: missing baseline group`);
    return;
  }

  const includeRuntime = opts?.includeRuntime ?? true;
  const runtimeProfiles = Array.isArray(opts?.runtimeProfiles) ? new Set(opts.runtimeProfiles) : null;
  const specs = [
    { key: "binaryRatio", label: "binary ratio", warnPct: sizeWarnPct },
    { key: "strippedRatio", label: "stripped ratio", warnPct: sizeWarnPct },
  ];
  if (includeRuntime) {
    specs.push({ key: "runtimeRatio", label: "runtime ratio", warnPct: runtimeWarnPct });
  }

  for (const profile of profiles) {
    const currentProfile = currentGroup[profile];
    const baselineProfile = baselineGroup[profile];
    if (!currentProfile || !baselineProfile) {
      warnings.push(`${groupLabel}.${profile}: missing data in current/baseline`);
      continue;
    }

    for (const spec of specs) {
      const currentValue = Number(currentProfile[spec.key]);
      const baselineValue = Number(baselineProfile[spec.key]);
      if (spec.key === "runtimeRatio" && runtimeProfiles !== null && !runtimeProfiles.has(profile)) {
        continue;
      }
      if (!Number.isFinite(currentValue) || !Number.isFinite(baselineValue) || baselineValue <= 0) {
        continue;
      }
      const maxAllowed = baselineValue * (1 + spec.warnPct / 100);
      if (currentValue > maxAllowed) {
        const increasePct = ((currentValue / baselineValue) - 1) * 100;
        warnings.push(
          `${groupLabel}.${profile}.${spec.label} +${increasePct.toFixed(2)}% ` +
            `(current=${currentValue.toFixed(6)}, baseline=${baselineValue.toFixed(6)}, budget=+${spec.warnPct.toFixed(2)}%)`
        );
      }
    }
  }
}

let baselineLoaded = null;
if (!updateBaseline) {
  if (!fs.existsSync(baselinePath)) {
    warnings.push(`baseline file not found: ${baselineDisplay}`);
  } else {
    baselineLoaded = JSON.parse(fs.readFileSync(baselinePath, "utf8"));
    const baselineDerived = baselineLoaded.derivedBaseline || {};
    compareGroup("hello_overhead", current.derived.helloOverheadRatios, baselineDerived.helloOverheadRatios, { includeRuntime: false });
    compareGroup("array_overhead", current.derived.arrayOverheadRatios, baselineDerived.arrayOverheadRatios, { includeRuntime: false });
    compareGroup("hot_loop_overhead", current.derived.hotLoopOverheadRatios, baselineDerived.hotLoopOverheadRatios, {
      includeRuntime: false,
    });
    compareGroup("hot_loop_inproc_overhead", current.derived.hotLoopInprocOverheadRatios, baselineDerived.hotLoopInprocOverheadRatios, {
      includeRuntime: true,
      runtimeProfiles: ["metal"],
    });
    compareGroup("chat_relative", current.derived.chatRelativeToMin, baselineDerived.chatRelativeToMin, { includeRuntime: true });
  }
}

const comparison = {
  schemaVersion: 1,
  generatedAt: current.generatedAt,
  mode: updateBaseline ? "update-baseline" : "compare",
  baselinePath: baselineDisplay,
  baselineAvailable: baselineLoaded != null || updateBaseline,
  warningCount: warnings.length,
  warnings,
};
fs.writeFileSync(comparisonJsonPath, `${JSON.stringify(comparison, null, 2)}\n`);
fs.writeFileSync(
  warningsPath,
  warnings.length > 0 ? `${warnings.join("\n")}\n` : ""
);

function formatRatio(v) {
  return Number(v).toFixed(3);
}

function ratioTable(title, ratioGroup) {
  const lines = [];
  lines.push(`### ${title}`);
  lines.push("| Profile | Binary x | Stripped x | Runtime x |");
  lines.push("| --- | ---: | ---: | ---: |");
  for (const profile of profiles) {
    const row = ratioGroup[profile];
    lines.push(
      `| ${profile} | ${formatRatio(row.binaryRatio)} | ${formatRatio(row.strippedRatio)} | ${formatRatio(row.runtimeRatio)} |`
    );
  }
  lines.push("");
  return lines.join("\n");
}

const summaryLines = [];
summaryLines.push("## HXRT Overhead Benchmarks");
summaryLines.push("");
summaryLines.push(`- Mode: \`${comparison.mode}\``);
summaryLines.push(`- Size budget: \`+${sizeWarnPct}%\``);
summaryLines.push(`- Runtime budget: \`+${runtimeWarnPct}%\``);
summaryLines.push(`- Runtime loops: hello=${helloIters}, array=${arrayIters}, hot_loop=${hotLoopIters}, hot_loop_inproc=${hotLoopInprocRuns}, chat=${chatIters}`);
if (haxeVersion.length > 0 || rustcVersion.length > 0) {
  summaryLines.push(`- Toolchain: ${haxeVersion || "haxe:unknown"} | ${rustcVersion || "rustc:unknown"}`);
}
summaryLines.push("");
summaryLines.push(ratioTable("Hello Overhead (x vs pure Rust hello; startup-weighted)", current.derived.helloOverheadRatios));
summaryLines.push(ratioTable("Array Overhead (x vs pure Rust array loop; startup-weighted)", current.derived.arrayOverheadRatios));
summaryLines.push(ratioTable("Hot Loop Overhead (x vs pure Rust hot loop case; startup-weighted)", current.derived.hotLoopOverheadRatios));
summaryLines.push(ratioTable("Hot Loop In-Process Overhead (x vs pure Rust hot loop in-process throughput)", current.derived.hotLoopInprocOverheadRatios));
summaryLines.push(ratioTable("Chat Profile Spread (x vs fastest/smallest chat profile in this run; startup-weighted)", current.derived.chatRelativeToMin));

const metalHotLoopTarget = 1.05;
const metalHotLoopRatio = Number(current.derived.hotLoopInprocOverheadRatios.metal.runtimeRatio);
summaryLines.push("### Target Tracking");
summaryLines.push(`- metal hot-loop in-process runtime target: <= ${metalHotLoopTarget.toFixed(3)}x pure Rust`);
summaryLines.push(
  `- metal hot-loop in-process runtime current: ${metalHotLoopRatio.toFixed(3)}x ` +
    `(${metalHotLoopRatio <= metalHotLoopTarget ? "target met" : "target not met"})`
);
summaryLines.push("");

if (warnings.length > 0) {
  summaryLines.push("### Soft Budget Warnings");
  for (const warning of warnings) {
    summaryLines.push(`- ${warning}`);
  }
} else {
  summaryLines.push("### Soft Budget Warnings");
  summaryLines.push("- none");
}
summaryLines.push("");

fs.writeFileSync(summaryPath, `${summaryLines.join("\n")}\n`);

console.log(`[hxrt-perf] mode=${comparison.mode} warnings=${warnings.length}`);
NODE

warning_count=0
if [[ -s "$warnings_txt" ]]; then
  while IFS= read -r warning; do
    [[ -n "$warning" ]] || continue
    warning_count=$((warning_count + 1))
    echo "::warning::[hxrt-perf] $warning"
  done < "$warnings_txt"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" && -f "$summary_md" ]]; then
  {
    echo ""
    cat "$summary_md"
    echo ""
  } >> "$GITHUB_STEP_SUMMARY"
fi

if [[ -f "$baseline_file" ]]; then
  cp "$baseline_file" "$results_dir/baseline_used.json"
fi

log "done (warnings=$warning_count)"
log "metrics: $(display_path "$current_json")"
log "comparison: $(display_path "$comparison_json")"
log "summary: $(display_path "$summary_md")"
