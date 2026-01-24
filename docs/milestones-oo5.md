# Milestones — `haxe.rust-oo5`

This doc mirrors the Beads epic `haxe.rust-oo5` and explains the intent behind each milestone.

## `haxe.rust-oo5.1` — Compiler hygiene: warnings + output polish

Goal: generated Rust should feel “production grade” (low noise, clean imports, fewer `unused_mut`, fewer style warnings).

Planned work:
- Import hygiene (TypeUsageTracker-driven `use` + `HxRef` only when needed, or fully-qualified paths).
- Better mutability inference and constructor/local fixes to reduce `unused_mut`.
- Portable mode style-warning policy: keep builds warning-free by default (snake_case naming + lint strategy so builds aren’t spammy).
- Optional strictness: `-D rust_deny_warnings` for users/CI that want warning-free output.

## `haxe.rust-oo5.2` — Rusty runtime + stdlib parity

Goal: expand `rust.*` so Rust-idiomatic apps can be written in Haxe without raw `__rust__` in app code.

Planned work:
- String surface: borrowed `Str` and owned `String` ergonomics (reduce clone churn while staying safe).
- Slices + iterators: iterator-first programming without exposing lifetimes in Haxe syntax.
- Path/fs/time primitives: enough to build real CLI/TUI apps cleanly.
- Error model helpers: improve Option/Result ergonomics and design a bridge between portable exceptions and rusty Result.
- Tooling glue: let framework code ship Rust modules via `@:rustExtraSrc(...)` (prefer over `-D rust_extra_src=...` in apps).

## `haxe.rust-oo5.3` — CI security guardrails

Goal: catch leaks and risky dependency changes early.

Implemented:
- Gitleaks secret scanning in CI.
- GitHub dependency review action on PRs.
- CodeQL analysis (Rust + JS/TS).
