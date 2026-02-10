#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAP_DIR="$ROOT_DIR/test/snapshot"

HAXE_BIN="${HAXE_BIN:-}"
if [[ -z "$HAXE_BIN" ]]; then
  if [[ -x "$ROOT_DIR/node_modules/.bin/haxe" ]]; then
    HAXE_BIN="$ROOT_DIR/node_modules/.bin/haxe"
  else
    HAXE_BIN="haxe"
  fi
fi

usage() {
  cat <<'EOF'
Usage: test/run-snapshots.sh [--case NAME] [--update] [--clippy]

Runs snapshot tests:
  - regenerates each test's out*/ via `haxe compile*.hxml`
  - optionally updates intended*/ (golden) outputs with --update
  - diffs intended*/ vs out*/
  - runs `cargo fmt` and `cargo build -q` for each generated crate
  - optionally runs `cargo clippy` correctness/suspicious lints for a small curated subset of cases

Options:
  --case NAME   Run a single snapshot case directory (by folder name).
  --update      Replace intended*/ with the newly generated out*/ (excluding Cargo.lock/target/_GeneratedFiles.json).
  --clippy      After `cargo build`, also run a curated `cargo clippy` check for selected cases.
               This intentionally does NOT enforce full clippy style cleanliness for generated code.
               Selection:
                 - If `--case` is set: runs for that case.
                 - Else if `SNAP_CLIPPY_CASES` is set: comma/space-separated list (e.g. "v1_smoke,idiomatic_profile").
                 - Else: default curated list (see script).

Snapshot variants:
  A case may include multiple compile files:
    - compile.hxml              (default variant) -> out/ and intended/
    - compile.<variant>.hxml    (extra variants)  -> out_<variant>/ and intended_<variant>/

  The runner always overrides `-D rust_output=...` so each compile file can stay minimal.
EOF
}

only_case=""
update_intended=0
run_clippy=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --case)
      only_case="${2:-}"
      shift 2
      ;;
    --update)
      update_intended=1
      shift
      ;;
    --clippy)
      run_clippy=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$HAXE_BIN" == */* ]]; then
  if [[ ! -x "$HAXE_BIN" ]]; then
    echo "error: haxe not found or not executable: $HAXE_BIN" >&2
    exit 2
  fi
else
  if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
    echo "error: haxe not found in PATH (HAXE_BIN=$HAXE_BIN)" >&2
    exit 2
  fi
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found in PATH" >&2
  exit 2
fi

# Snapshot harness performance + disk hygiene:
# Build all generated crates into a shared target directory so we don't create
# `*/out*/target` for every single snapshot case.
#
# Override with:
# - `SNAP_CARGO_TARGET_DIR=/path/to/dir`
# - or pre-set `CARGO_TARGET_DIR`
if [[ -z "${CARGO_TARGET_DIR:-}" ]]; then
  SNAP_CARGO_TARGET_DIR="${SNAP_CARGO_TARGET_DIR:-$ROOT_DIR/.cache/snapshots-target}"
  export CARGO_TARGET_DIR="$SNAP_CARGO_TARGET_DIR"
fi

fail=0

should_run_clippy_for_case() {
  local case_name="$1"

  [[ "$run_clippy" == "1" ]] || return 1

  if [[ -n "$only_case" ]]; then
    [[ "$case_name" == "$only_case" ]]
    return
  fi

  local configured="${SNAP_CLIPPY_CASES:-}"
  if [[ -n "$configured" ]]; then
    # Normalize: commas -> spaces, then match whole words.
    configured="${configured//,/ }"
    [[ " $configured " == *" $case_name "* ]]
    return
  fi

  # Default curated list: keep this short so CI stays fast.
  [[ "$case_name" == "v1_smoke" || "$case_name" == "idiomatic_profile" || "$case_name" == "rusty_v1_smoke" ]]
}

for case_dir in "$SNAP_DIR"/*; do
  [[ -d "$case_dir" ]] || continue
  # At least one compile file must exist for this snapshot case.
  has_compile=0
  if [[ -f "$case_dir/compile.hxml" ]]; then
    has_compile=1
  else
    for _ in "$case_dir"/compile.*.hxml; do
      if [[ -f "$_" ]]; then
        has_compile=1
        break
      fi
    done
  fi
  [[ "$has_compile" == "1" ]] || continue

  case_name="$(basename "$case_dir")"
  if [[ -n "$only_case" && "$case_name" != "$only_case" ]]; then
    continue
  fi

  echo "[snap] $case_name"

  compile_files=()
  if [[ -f "$case_dir/compile.hxml" ]]; then
    compile_files+=("compile.hxml")
  fi
  for f in "$case_dir"/compile.*.hxml; do
    [[ -f "$f" ]] || continue
    compile_files+=("$(basename "$f")")
  done

  for compile_file in "${compile_files[@]}"; do
    variant=""
    if [[ "$compile_file" != "compile.hxml" ]]; then
      variant="${compile_file#compile.}"
      variant="${variant%.hxml}"
      variant="${variant//./_}"
    fi

    out_base="out"
    intended_base="intended"
    if [[ -n "$variant" ]]; then
      out_base="out_${variant}"
      intended_base="intended_${variant}"
    fi

    out_dir="$case_dir/$out_base"
    intended_dir="$case_dir/$intended_base"

    expects_stdout=0
    if [[ -f "$intended_dir/stdout.txt" ]]; then
      expects_stdout=1
    fi

    if ! grep -qE '^-main[[:space:]]+' "$case_dir/$compile_file"; then
      echo "  error: $compile_file must include '-main <Class>' (required for reliable main detection)" >&2
      fail=1
      continue
    fi

    rm -rf "$out_dir"
    # Snapshots do their own cargo build step below; keep codegen-only during compilation.
    (cd "$case_dir" && "$HAXE_BIN" "$compile_file" -D rust_output="$out_base" -D rust_no_build)

    if [[ -f "$out_dir/Cargo.toml" ]]; then
      if ! (cd "$out_dir" && cargo fmt >/dev/null); then
        echo "  cargo fmt failed: $out_dir" >&2
        fail=1
      fi
      if ! (cd "$out_dir" && cargo build -q); then
        echo "  cargo build failed: $out_dir" >&2
        fail=1
      fi
      if should_run_clippy_for_case "$case_name"; then
        if ! (cd "$out_dir" && cargo clippy -- -A clippy::all -D clippy::correctness -D clippy::suspicious >/dev/null); then
          echo "  cargo clippy failed: $out_dir" >&2
          fail=1
        fi
      fi
    fi

    if [[ "$update_intended" == "1" ]]; then
      rm -rf "$intended_dir"
      mkdir -p "$intended_dir"
      rsync -a --delete \
        --exclude "_GeneratedFiles.json" \
        --exclude "Cargo.lock" \
        --exclude "stdout.txt" \
        --exclude "target" \
        "$out_dir/" "$intended_dir/"
    fi

    if [[ ! -d "$intended_dir" ]]; then
      echo "  error: missing $intended_base/ directory: $intended_dir" >&2
      echo "  hint: run: test/run-snapshots.sh --case $case_name --update" >&2
      fail=1
      continue
    fi

    if [[ -f "$out_dir/Cargo.toml" ]]; then
      # Optional: runtime stdout snapshot (deterministic cases only).
      # If intended*/stdout.txt exists (or existed before --update), run the compiled binary and compare stdout.
      if [[ "$expects_stdout" == "1" ]]; then
        actual_stdout="$case_dir/.stdout.actual"
        if ! (cd "$out_dir" && cargo run -q) >"$actual_stdout"; then
          echo "  cargo run failed: $out_dir" >&2
          fail=1
        else
          if [[ "$update_intended" == "1" ]]; then
            cp "$actual_stdout" "$intended_dir/stdout.txt"
          fi
          if ! diff -u "$intended_dir/stdout.txt" "$actual_stdout"; then
            fail=1
          fi
        fi
        rm -f "$actual_stdout"
      fi
    fi

    if ! diff -ru \
      -x "_GeneratedFiles.json" \
      -x "Cargo.lock" \
      -x "stdout.txt" \
      -x "target" \
      "$intended_dir" "$out_dir"; then
      fail=1
    fi
  done
done

exit "$fail"
