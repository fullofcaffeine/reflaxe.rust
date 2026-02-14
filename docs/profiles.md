# Profiles (`-D reflaxe_rust_profile=...`)

This target supports three compile-time profiles. The profile is the main contract for "what kind of Rust
you want to author from Haxe."

## Terminology

- **Haxe-first** in this project means the `portable` profile.
- **Rust-first** in this project means the `rusty` profile.
- `idiomatic` is a bridge profile: same semantics as `portable`, cleaner Rust output.

## Profile selector

```bash
-D reflaxe_rust_profile=portable|idiomatic|rusty
```

Compatibility alias:

```bash
-D rust_idiomatic
```

## Capability Matrix (What Is And Is Not Practical)

| Profile | Best for | What is practical | What is intentionally limited / not possible |
| --- | --- | --- | --- |
| `portable` (default) | Haxe-first teams and cross-target code | Haxe-style APIs, predictable Haxe semantics, lowest migration cost | Not intended for explicit ownership/lifetime-oriented API design; borrow-sensitive Rust tuning is secondary |
| `idiomatic` | Teams that want cleaner generated Rust without changing app semantics | Same behavior as portable with cleaner emitted Rust (lint/noise reduction) | Still not a Rust-first authoring model; same semantic constraints as portable |
| `rusty` | Rust-aware teams that want stronger ownership/borrow intent in Haxe code | `rust.*` surfaces (`Ref`, `MutRef`, `Slice`, `Option`, `Result`, etc.), explicit borrow-scoped APIs, async preview | Full Rust lifetime modeling is still not available; long-lived borrowed API designs remain constrained by Haxe type system |

## Rust Concept Leverage By Profile

| Rust concept | `portable` | `idiomatic` | `rusty` |
| --- | --- | --- | --- |
| Ownership-aware API design | Low | Low-Medium | High |
| Borrow-shaped signatures (`&T` / `&mut T`) | Limited, mostly runtime/internal | Limited, mostly runtime/internal | First-class via `rust.Ref` / `rust.MutRef` |
| Slice/`&str` style APIs | Limited | Limited | First-class via `rust.Slice` / `rust.Str` |
| Explicit `Option`/`Result` surfaces | Optional | Optional | Recommended default |
| Rust async/await preview | No | No | Yes (`-D rust_async_preview`) |
| Full lifetime generics parity with handwritten Rust | No | No | No (by design in v1) |

## Pros / Cons Summary

### `portable` (Haxe-first)

Pros:
- Best default for teams prioritizing Haxe semantics and portability.
- Lowest cognitive load for non-Rust specialists.

Cons:
- Less leverage of advanced Rust ownership patterns.
- Generated code may require more runtime bridges than a Rust-first design.

### `idiomatic` (bridge)

Pros:
- Cleaner Rust output without forcing a Rust-first app architecture.
- Good intermediate step before adopting Rusty surfaces.

Cons:
- Does not unlock the full Rusty API surface philosophy.
- Same fundamental semantic constraints as `portable`.

### `rusty` (Rust-first)

Pros:
- Most expressive profile for borrow-aware and ownership-aware API design.
- Stronger alignment with Rust mental models (`Option`, `Result`, slices, refs).

Cons:
- Higher design discipline required (explicit ownership boundaries).
- Still not a full replacement for handwritten Rust lifetime design.

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

## Lifetime Reality Check

All profiles compile to Rust that is checked by `rustc`, but none can expose the full Rust lifetime
type system directly in Haxe signatures today.

- `portable`/`idiomatic`: treat this as an implementation detail and prefer owned/high-level APIs.
- `rusty`: use borrow-scoped patterns and borrow tokens; this gives useful lifetime-like constraints,
  but not full generic lifetime expressiveness.

For a concrete design discussion, see [Lifetime Encoding Design](lifetime-encoding.md).

## Where profile behavior is validated

- Snapshot matrix under `test/snapshot/*`.
- Rusty-specific variants under `compile.rusty.hxml` and `intended_rusty/` cases.
- Full CI-style local validation via `npm run test:all`.

## Related docs

- `docs/start-here.md`
- `docs/rusty-profile.md`
- `docs/lifetime-encoding.md`
- `docs/v1.md`
- `docs/defines-reference.md`
