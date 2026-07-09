# Milestones — Ongoing Quality Program

This document explains the intent behind the current quality milestones in plain language.

Historical tracker anchor: `haxe.rust-oo5` (closed).
Closed continuation evidence: `haxe_rust-mfmm` and follow-up `haxe_rust-sqon`.

This page records the closed `oo5` quality baseline and continuation guidance. It is
not a new release gate by itself; it is the ongoing quality queue for compiler polish, Rust-first
API depth, and CI guardrail maintenance. New work should use fresh Beads issues rather than
reopening historical `haxe.rust-oo5` / `haxe.rust-oo6` IDs.

## Milestone 1 — Compiler hygiene: warnings + output polish

Historical tracker: `haxe.rust-oo5.1`.

Goal: generated Rust should feel production-grade (low noise, clean imports, fewer `unused_mut`, fewer style warnings).

Current baseline:

- `-D rust_deny_warnings` is already implemented and emits `#![deny(warnings)]` in the generated
  crate root. It is documented in [Defines reference](defines-reference.md) and covered by
  `test/snapshot/deny_warnings` plus selected async/concurrency snapshots.
- The compiler already emits crate-level lint policy for generated roots, including
  `#![allow(dead_code)]` and `#![allow(type_alias_bounds)]`, so user opt-in strictness stays focused
  on actionable generated-code warnings.
- Existing cleanup passes cover several known warning classes, including diverging-return cleanup,
  deferred-local mutability inference, `while true` to `loop`, unreachable enum-match wildcard
  pruning, and unused catch/self argument cleanup.

Remaining work:

- Import hygiene (`use` only when needed, avoid over-qualification noise).
- Better mutability inference and constructor/local fixes as new `unused_mut` or
  `unused_assignments` cases are reproduced.
- Portable mode style-warning policy: keep builds warning-light by default (snake_case naming + lint strategy so builds are readable).
- Broader deny-warnings coverage for newly discovered generated-output warning classes.

Closed continuation slices:

- `haxe_rust-mfmm` — sync the closed `oo5` baseline docs and std override mapping.
- `haxe_rust-sqon` — audited import-hygiene output shape and landed the nested-module path fix.

Future slices should start from fresh Beads issues with current emitted-Rust evidence rather than
reusing these closed continuation IDs.

## Milestone 2 — Rust-first runtime + stdlib parity

Historical tracker: `haxe.rust-oo5.2`.

Goal: expand `rust.*` so Rust-first apps can be written in Haxe without raw `__rust__` in app code.

Planned work:
- String surface: borrowed `Str` and owned `String` ergonomics (reduce clone churn while staying safe).
- Slices + iterators: iterator-first programming without exposing lifetimes in Haxe syntax.
- Path/fs/time primitives: enough to build real CLI/TUI apps cleanly.
- Error model helpers: improve Option/Result ergonomics and design a bridge between portable exceptions and Rust-first `Result`.
- Tooling glue: let framework code ship Rust modules via `@:rustExtraSrc(...)` (prefer over `-D rust_extra_src=...` in apps).

## Milestone 3 — CI security guardrails

Historical tracker: `haxe.rust-oo5.3`.

Goal: catch leaks and risky dependency changes early.

Implemented baseline:

- Gitleaks secret scanning in CI.
- GitHub dependency review action on PRs.
- CodeQL analysis (Rust + JS/TS).

Future changes should stay evidence-driven: add or update a focused Beads issue when guard behavior,
workflow coverage, or release evidence changes.
