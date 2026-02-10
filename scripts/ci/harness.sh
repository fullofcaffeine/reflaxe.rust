#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root_dir"

run_example() {
  local dir="$1"
  local hxml="$2"
  local out_dir="$3"
  local run_tests="$4"
  local run_bin="$5"

  echo "[harness] example: ${dir} (${hxml} -> ${out_dir})"
  (cd "$dir" && haxe "$hxml")

  if [[ "$run_tests" -eq 1 ]]; then
    (cd "$dir/$out_dir" && cargo test -q)
  fi

  if [[ "$run_bin" -eq 1 ]]; then
    (cd "$dir/$out_dir" && cargo run -q)
  fi
}

echo "[harness] snapshots"
bash test/run-snapshots.sh --clippy

echo "[harness] examples"
run_example examples/hello compile.hxml out 0 1
run_example examples/classes compile.hxml out 0 1
run_example examples/sys_file_io compile.ci.hxml out_ci 0 1
run_example examples/sys_process compile.ci.hxml out_ci 0 1
run_example examples/sys_net_loopback compile.ci.hxml out_ci 0 1
run_example examples/sys_thread_smoke compile.ci.hxml out_ci 0 1
run_example examples/thread_pool_smoke compile.ci.hxml out_ci 0 1
run_example examples/serde_json compile.ci.hxml out_ci 0 1
run_example examples/serde_json compile.rusty.ci.hxml out_ci_rusty 0 1
run_example examples/bytes_ops compile.ci.hxml out_ci 1 1
run_example examples/bytes_ops compile.rusty.ci.hxml out_ci_rusty 1 1
run_example examples/tui_todo compile.ci.hxml out_ci 1 1
run_example examples/tui_todo compile.rusty.ci.hxml out_ci_rusty 1 1

echo "[harness] ok"
