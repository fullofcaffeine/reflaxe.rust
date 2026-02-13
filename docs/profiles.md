# Profiles (`-D reflaxe_rust_profile=...`)

This target supports three compile-time profiles.

## Why this matters

Users usually talk about two modes:

- portable Haxe workflows,
- rusty Haxe workflows.

The compiler adds a practical middle option (`idiomatic`) so teams can improve Rust output quality without changing app semantics.

## Profile selector

```bash
-D reflaxe_rust_profile=portable|idiomatic|rusty
```

Compatibility alias:

```bash
-D rust_idiomatic
```

## Profile comparison

| Profile | Who it is for | Semantics | Output style |
| --- | --- | --- | --- |
| `portable` (default) | Haxe-first teams and cross-target code | Prioritizes Haxe portability | Predictable, may be less Rust-idiomatic |
| `idiomatic` | Teams that want cleaner Rust output | Same as portable | Cleaner blocks, fewer warnings/noise |
| `rusty` | Rust-aware teams using lower-level control | Rust-first APIs (`rust.*`) | More explicit ownership/borrow-oriented output |

## String representation defaults

- Portable and idiomatic default to nullable string mode.
- Rusty defaults to legacy non-null Rust `String` mode.
- You can override explicitly with:
  - `-D rust_string_nullable`
  - `-D rust_string_non_nullable`

## Injection and boundary policy

For production apps and examples, preferred policy is:

- no direct `__rust__` in app code,
- keep Rust details behind typed APIs (externs, wrappers, runtime/std layers).

Repo enforcement options:

- `-D reflaxe_rust_strict_examples` for examples/snapshots.
- `-D reflaxe_rust_strict` for user projects that want strict enforcement.

## Where profile behavior is validated

- Snapshot matrix under `test/snapshot/*`.
- Rusty-specific variants under `compile.rusty.hxml` and `intended_rusty/` cases.
- Full CI-style local validation via `npm run test:all`.

## Related docs

- `docs/start-here.md`
- `docs/rusty-profile.md`
- `docs/v1.md`
- `docs/defines-reference.md`
