#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAP_DIR="$ROOT_DIR/test/snapshot"

usage() {
  cat <<'EOF'
Usage: test/run-snapshots.sh [--case NAME] [--update]

Runs snapshot tests:
  - regenerates each test's out/ via `haxe compile.hxml`
  - optionally updates intended/ (golden) outputs with --update
  - diffs intended/ vs out/
  - runs `cargo fmt` and `cargo build -q` for each generated crate

Options:
  --case NAME   Run a single snapshot case directory (by folder name).
  --update      Replace intended/ with the newly generated out/ (excluding Cargo.lock/target/_GeneratedFiles.json).
EOF
}

only_case=""
update_intended=0

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

if ! command -v haxe >/dev/null 2>&1; then
  echo "error: haxe not found in PATH" >&2
  exit 2
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found in PATH" >&2
  exit 2
fi

fail=0

for case_dir in "$SNAP_DIR"/*; do
  [[ -d "$case_dir" ]] || continue
  [[ -f "$case_dir/compile.hxml" ]] || continue

  case_name="$(basename "$case_dir")"
  if [[ -n "$only_case" && "$case_name" != "$only_case" ]]; then
    continue
  fi

  echo "[snap] $case_name"

  expects_stdout=0
  if [[ -f "$case_dir/intended/stdout.txt" ]]; then
    expects_stdout=1
  fi

  if ! grep -qE '^-main[[:space:]]+' "$case_dir/compile.hxml"; then
    echo "  error: compile.hxml must include '-main <Class>' (required for reliable main detection)" >&2
    fail=1
    continue
  fi

  rm -rf "$case_dir/out"
  (cd "$case_dir" && haxe compile.hxml)

  if [[ -f "$case_dir/out/Cargo.toml" ]]; then
    if ! (cd "$case_dir/out" && cargo fmt >/dev/null); then
      echo "  cargo fmt failed: $case_dir/out" >&2
      fail=1
    fi
    if ! (cd "$case_dir/out" && cargo build -q); then
      echo "  cargo build failed: $case_dir/out" >&2
      fail=1
    fi
  fi

  if [[ "$update_intended" == "1" ]]; then
    rm -rf "$case_dir/intended"
    mkdir -p "$case_dir/intended"
    rsync -a --delete \
      --exclude "_GeneratedFiles.json" \
      --exclude "Cargo.lock" \
      --exclude "stdout.txt" \
      --exclude "target" \
      "$case_dir/out/" "$case_dir/intended/"
  fi

  if [[ ! -d "$case_dir/intended" ]]; then
    echo "  error: missing intended/ directory: $case_dir/intended" >&2
    echo "  hint: run: test/run-snapshots.sh --case $case_name --update" >&2
    fail=1
    continue
  fi

  if [[ -f "$case_dir/out/Cargo.toml" ]]; then
    # Optional: runtime stdout snapshot (deterministic cases only).
    # If intended/stdout.txt exists (or existed before --update), run the compiled binary and compare stdout.
    if [[ "$expects_stdout" == "1" ]]; then
      actual_stdout="$case_dir/.stdout.actual"
      if ! (cd "$case_dir/out" && cargo run -q) >"$actual_stdout"; then
        echo "  cargo run failed: $case_dir/out" >&2
        fail=1
      else
        if [[ "$update_intended" == "1" ]]; then
          cp "$actual_stdout" "$case_dir/intended/stdout.txt"
        fi
        if ! diff -u "$case_dir/intended/stdout.txt" "$actual_stdout"; then
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
    "$case_dir/intended" "$case_dir/out"; then
    fail=1
  fi
done

exit "$fail"
