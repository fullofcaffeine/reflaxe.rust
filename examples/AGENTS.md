# Agent Instructions for `examples/`

- Examples are treated as “final apps”: do not use `untyped __rust__()` or `reflaxe.rust.macros.RustInjection` in example code.
- If an example needs native Rust interop, add a small wrapper API in `std/` and call that from the example.
- Keep examples deterministic and snapshot-friendly in CI: interactive TTY flows are allowed, but they must provide
  headless deterministic render paths (for example ratatui `TestBackend`) and non-TTY fallback behavior so `cargo run`
  / `cargo test` never hang in automation.
- Example `.hxml` files should include `-D reflaxe_rust_strict_examples` to enforce boundaries.
- Prefer DRY examples: keep a single source tree and add additional `compile.*.hxml` build files (plus a small `#if <define>` shim) rather than duplicating an entire example directory per profile.
- Example claims must match what automation actually observes. Keep each example classified in
  `docs/testing-surface-scorecards.json` as a flagship application, capability showcase, or compile-only
  snippet, and name its independent product surfaces there. A source snapshot alone cannot support a
  runtime, no-hxrt, package, portability, or platform claim; claim-bearing examples must use the real
  backend plus the strict Cargo build and runtime/system observer appropriate to that claim.
