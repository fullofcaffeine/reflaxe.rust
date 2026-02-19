# Profiles (`-D reflaxe_rust_profile=...`)

This target supports four compile-time profiles. The profile is the main contract for "what kind of Rust
you want to author from Haxe."

## Terminology

- **Haxe-first** in this project means the `portable` profile.
- **Rust-first** in this project means the `rusty` or `metal` profiles.
- `idiomatic` is a bridge profile: same semantics as `portable`, cleaner Rust output.
- `metal` is experimental and additive: Rusty+ with typed low-level interop façade.

## Profile selector

```bash
-D reflaxe_rust_profile=portable|idiomatic|rusty|metal
```

Compatibility alias:

```bash
-D rust_idiomatic
-D rust_metal
```

## Capability Matrix (What Is And Is Not Practical)

| Profile | Best for | What is practical | What is intentionally limited / not possible |
| --- | --- | --- | --- |
| `portable` (default) | Haxe-first teams and cross-target code | Haxe-style APIs, predictable Haxe semantics, lowest migration cost | Not intended for explicit ownership/lifetime-oriented API design; borrow-sensitive Rust tuning is secondary |
| `idiomatic` | Teams that want cleaner generated Rust without changing app semantics | Same behavior as portable with cleaner emitted Rust (lint/noise reduction) | Still not a Rust-first authoring model; same semantic constraints as portable |
| `rusty` | Rust-aware teams that want stronger ownership/borrow intent in Haxe code | `rust.*` surfaces (`Ref`, `MutRef`, `Slice`, `Option`, `Result`, etc.), explicit borrow-scoped APIs, async preview | Full Rust lifetime modeling is still not available; long-lived borrowed API designs remain constrained by Haxe type system |
| `metal` (experimental) | Rust-heavy teams that occasionally need low-level control beyond current typed wrappers | Rusty surface + typed low-level façade (`rust.metal.Code.*`) + strict app-boundary defaults | Still no full lifetime generics parity; low-level snippets still require discipline and review |

## Rust Concept Leverage By Profile

| Rust concept | `portable` | `idiomatic` | `rusty` | `metal` |
| --- | --- | --- | --- | --- |
| Ownership-aware API design | Low | Low-Medium | High | High+ |
| Borrow-shaped signatures (`&T` / `&mut T`) | Limited, mostly runtime/internal | Limited, mostly runtime/internal | First-class via `rust.Ref` / `rust.MutRef` | First-class via `rust.Ref` / `rust.MutRef` |
| Slice/`&str` style APIs | Limited | Limited | First-class via `rust.Slice` / `rust.Str` | First-class via `rust.Slice` / `rust.Str` |
| Explicit `Option`/`Result` surfaces | Optional | Optional | Recommended default | Recommended default |
| Typed low-level Rust snippets | Not a goal | Not a goal | Limited | Yes (`rust.metal.Code.*`) |
| Rust async/await preview | No | No | Yes (`-D rust_async_preview`) | Yes (`-D rust_async_preview`) |
| Full lifetime generics parity with handwritten Rust | No | No | No (by design in v1) | No (by design in v1) |

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

### `metal` (experimental Rust-first+)

Pros:
- Keeps Rusty strengths while adding a typed low-level interop surface.
- Enables strict default policy for app-side injection boundaries.

Cons:
- Experimental profile: API shape may evolve faster than stable profiles.
- Typed low-level snippets still need careful review for maintainability.

## Performance intent by profile

Performance policy is profile-sensitive:

- `metal`: target profile for near-pure-Rust runtime behavior in hot paths.
  - Stretch goal: keep steady-state runtime ratios very close to pure Rust (`~1.00x`, practical warning target currently `<=1.05x` on hot-loop class benchmarks).
- `rusty`: Rust-first profile that should trend close to metal where low-level escape hatches are not required.
- `idiomatic`: no semantic shift vs portable; performance should stay in the same envelope unless specific codegen improvements are intentional.
- `portable`: accepts the largest intentional overhead in exchange for Haxe-first ergonomics and semantic portability guarantees.

Tracked benchmark details live in [HXRT overhead benchmarks](perf-hxrt-overhead.md).

## String representation defaults

- Portable and idiomatic default to nullable string mode.
- Rusty and metal default to legacy non-null Rust `String` mode.
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
- `metal` enables strict app-boundary mode by default (typed framework façades remain allowed).

## Lifetime Reality Check

All profiles compile to Rust that is checked by `rustc`, but none can expose the full Rust lifetime
type system directly in Haxe signatures today.

- `portable`/`idiomatic`: treat this as an implementation detail and prefer owned/high-level APIs.
- `rusty`/`metal`: use borrow-scoped patterns and borrow tokens; this gives useful lifetime-like constraints,
  but not full generic lifetime expressiveness.

For a concrete design discussion, see [Lifetime Encoding Design](lifetime-encoding.md).

## Where profile behavior is validated

- Snapshot matrix under `test/snapshot/*`.
- Rusty/metal variants under `compile.rusty.hxml` / `compile.metal.hxml` and corresponding `intended_*` cases.
- Cross-profile flagship app: `examples/chat_loopback` (`compile.portable*.hxml`, `compile.idiomatic*.hxml`, `compile.rusty*.hxml`, `compile.metal*.hxml`).
- Cross-profile profile-idiom mini-app: `examples/profile_storyboard` (`compile.portable*.hxml`, `compile.idiomatic*.hxml`, `compile.rusty*.hxml`, `compile.metal*.hxml`).
- Full CI-style local validation via `npm run test:all`.

## Related docs

- `docs/start-here.md`
- `docs/examples-matrix.md`
- `docs/rusty-profile.md`
- `docs/metal-profile.md`
- `docs/lifetime-encoding.md`
- `docs/v1.md`
- `docs/defines-reference.md`
