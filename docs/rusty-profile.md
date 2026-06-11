# Profile Migration Guide (Removed Rusty/Idiomatic Selectors)

The `rusty` profile selector was removed.

## What changed

- Removed: `-D reflaxe_rust_profile=rusty`
- Removed: `-D reflaxe_rust_profile=idiomatic`
- Supported now: `-D reflaxe_rust_profile=portable|metal`

## Migration mapping

- old `idiomatic` -> use `portable`
- old `rusty` -> use `metal`

This mapping is about **semantic contracts**, not about giving up idiomatic Rust output. Idiomatic
Rust remains an output-quality goal in both supported profiles:

- `portable` should emit clean, efficient, Rust-recognizable code whenever that preserves Haxe
  semantics.
- `metal` should emit clean, efficient Rust while honoring its Rust-first source contract and
  stricter boundary rules.

## Why

The public profile model was simplified to two explicit contracts:

- `portable`: Haxe-portable semantics first.
- `metal`: Rust-first performance profile with strict typed boundaries.

This removes profile ambiguity and keeps optimization policy focused on clear target behaviors.
In short: profile selectors choose semantics; "idiomatic" describes the desired quality of the
generated Rust across profiles.

## Command examples

Before:

```bash
-D reflaxe_rust_profile=idiomatic
-D reflaxe_rust_profile=rusty
```

After:

```bash
-D reflaxe_rust_profile=portable
-D reflaxe_rust_profile=metal
```
