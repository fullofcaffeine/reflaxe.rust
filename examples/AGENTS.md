# Agent Instructions for `examples/`

- Examples are treated as “final apps”: do not use `untyped __rust__()` or `reflaxe.rust.macros.RustInjection` in example code.
- If an example needs native Rust interop, add a small wrapper API in `std/` and call that from the example.
- Keep examples deterministic and snapshot-friendly (no real TTY I/O; prefer headless backends like ratatui `TestBackend`).
- Example `.hxml` files should include `-D reflaxe_rust_strict_examples` to enforce boundaries.
- Prefer DRY examples: keep a single source tree and add additional `compile.*.hxml` build files (plus a small `#if <define>` shim) rather than duplicating an entire example directory per profile.
