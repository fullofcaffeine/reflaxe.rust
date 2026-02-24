# Rusty Profile Migration Guide

The `rusty` profile selector was removed.

## What changed

- Removed: `-D reflaxe_rust_profile=rusty`
- Removed: `-D reflaxe_rust_profile=idiomatic`
- Supported now: `-D reflaxe_rust_profile=portable|metal`

## Migration mapping

- old `idiomatic` -> use `portable`
- old `rusty` -> use `metal`

## Why

The public profile model was simplified to two explicit contracts:

- `portable`: Haxe-portable semantics first.
- `metal`: Rust-first performance profile with strict typed boundaries.

This removes profile ambiguity and keeps optimization policy focused on clear target behaviors.

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
