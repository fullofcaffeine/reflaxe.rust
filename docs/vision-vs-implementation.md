# Vision vs Implementation (reality check)

This document validates the project vision against what is implemented today.
It is written for users who want an honest production-readiness picture without reading compiler internals first.

## Vision statement (simplified)

The intended product is:

- a production-grade Haxe 4.3.7 -> Rust target,
- usable by non-Rust experts in a portable mode,
- with an opt-in Rust-first mode for low-level control,
- while still allowing escape hatches when needed.

## Alignment matrix

### 1) “Compile Haxe to native Rust binaries by default”

- Status: **Aligned**
- Evidence:
  - `-D rust_output=...` generates a Cargo crate.
  - compiler runs Cargo build by default unless `-D rust_no_build` is set.
- Notes:
  - this is already the default workflow for examples and CI.

### 2) “Two usage styles: portable and Rust-first”

- Status: **Mostly aligned, with one clarification**
- Clarification:
  - implementation has **three** profiles: `portable`, `idiomatic`, `rusty`.
  - `idiomatic` is a middle ground: same semantics as portable, cleaner Rust output.
- Practical guidance:
  - choose `portable` for cross-target code,
  - `idiomatic` for cleaner generated Rust without changing app model,
  - `rusty` for Rust-oriented APIs and ownership-aware authoring.

### 3) “Users should not need raw Rust in app code”

- Status: **Aligned (policy + enforcement available)**
- Evidence:
  - repo policy: apps/examples should avoid direct `__rust__`.
  - strict define for examples/tests: `-D reflaxe_rust_strict_examples`.
  - interop path exists through typed externs/metadata and framework wrappers.
- Remaining risk:
  - complex interop areas still need continued std/runtime wrapper expansion to keep app code fully typed.

### 4) “Full stdlib/sys parity for production 1.0”

- Status: **Partially aligned (critical work remains)**
- Evidence:
  - parity epic exists and is the formal 1.0 gate: `haxe.rust-4jb`.
  - most dependency work is already closed.
  - one P0 blocker remains in progress: `haxe.rust-f63` (String nullability representation).
- Impact:
  - until `f63` closes, full parity claim is incomplete.

### 5) “Battle-tested with a real app harness”

- Status: **Partially aligned**
- Evidence:
  - advanced TUI harness epic exists: `haxe.rust-cu0`.
  - most children are done (scripted scenarios, persistence, multi-screen runtime).
  - animations/effects task still open: `haxe.rust-vrd`.
- Impact:
  - compiler is already exercised by non-trivial app flows, but harness polish/depth is still expanding.

## Gaps to close before 1.0 claim

1. Close `haxe.rust-f63` (nullable string representation end-to-end).
2. Finish docs parity task `haxe.rust-cfh` (stability contract docs match runtime/codegen reality).
3. Complete remaining advanced TUI harness work (`haxe.rust-vrd`) and keep it in CI.
4. Keep `test:all` as required green gate on every push/PR.

## What this means for users today

- You can already build and ship real native Rust apps with this target.
- The safest current production posture is:
  - use `portable` or `idiomatic` unless you need Rust-first APIs,
  - use typed interop (`extern`/metadata/wrappers) before raw injections,
  - keep CI strict with `npm run test:all`.
- Treat 1.0 as “close, but not final” until the remaining P0/P1 parity work closes.
