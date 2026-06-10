# Portable Near-Native Guidance

This page answers the practical post-`1.0` question for performance-oriented teams:

- how close can `portable` get to native Rust output,
- when is `metal` still the right choice,
- where `reflaxe.std` fits,
- and what kind of optimization work is allowed without blurring the public contract.

## Why this exists

`reflaxe.rust` now has:

- a stable public `portable|metal` contract model,
- evidence-backed release posture,
- targeted performance baselines,
- and a small but real `reflaxe.std` portable idiom slice.

What users still need is one clear answer to the strategic question:

> Can I stay in portable mode and still get Rust-native output quality?

The answer is "sometimes yes, by design, but not by silently changing contracts."

## What "near-native" means here

For this backend, "near-native" does **not** mean:

- every portable program will match hand-written Rust,
- every stdlib/runtime-heavy flow is already optimized to the same degree,
- or `portable` is secretly a native Rust profile in disguise.

It **does** mean:

- when a portable abstraction maps cleanly to a native Rust representation, the backend should
  lower to that native representation instead of paying avoidable wrapper/runtime tax,
- when portable code stays inside semantics the compiler/runtime can model efficiently, emitted Rust
  should trend toward code a Rust developer would actually recognize,
- and any remaining gap should come from conservative lowering/runtime obligations, not from a
  second-class representation choice.

Current concrete examples:

- `reflaxe.std.Option<T>` -> Rust `Option<T>`
- `reflaxe.std.Result<T, E>` -> Rust `Result<T, E>`

That is a backend optimization choice in service of the portable contract. It is **not** permission
to treat portable code as native-lane code.

## Contract rule: optimization is allowed, contract switching is not

This is the rule that keeps the model honest:

- `portable` remains a portable/Haxe-first contract.
- `metal` remains the Rust-first contract.
- lowering may choose the best native Rust representation when semantics match,
- but lowering must not silently turn portable code into native-lane code.

Examples:

- Allowed:
  - lowering `reflaxe.std.Option/Result` to Rust `Option/Result`
  - removing avoidable clones/temporaries in portable output
  - using better formatter/lowering paths when they preserve portable semantics
- Not allowed:
  - silently treating `rust.*` imports as portable
  - widening raw authority because a hot path would be faster
  - changing observable portable semantics just to look more Rust-like

## When `portable` is already the right answer

Choose `portable` when:

- you want cross-target intent or migration headroom,
- your team primarily thinks in Haxe semantics,
- you want the default, documented contract,
- or your "Rustiness" comes from the backend lowering quality rather than native-only APIs.

Portable is already a good fit when:

- the code is mostly typed business/application logic,
- the hot data shapes can lower cleanly,
- the runtime boundary is not the dominant cost,
- and you do not need Rust-only APIs as part of the source contract.

Portable does **not** automatically mean "wrapper-heavy" or "obviously non-Rusty" output on this
backend. The backend should keep removing avoidable representation and lowering tax where semantics
permit.

## When `metal` is still the right answer

Choose `metal` when the source contract itself should be Rust-first.

That usually means:

- performance-sensitive paths that truly want Rust-native surfaces in source,
- explicit use of `rust.*` / `rust.metal.*` APIs,
- tighter boundary rules as part of the team policy,
- minimal-runtime / no-`hxrt` work,
- or code that is intentionally authored as Rust-flavored Haxe rather than portable Haxe.

`metal` is not "portable with more courage." It is a different public contract.

Use it when you want that contract on purpose, not because the backend might optimize better.

## Where `reflaxe.std` fits

`reflaxe.std` is the portable idiom layer, not a hidden native-lane alias pack.

Current Rust-local truth:

- local adoption is real for `Option` / `Result`,
- those abstractions lower directly to native Rust `Option` / `Result`,
- adapters exist for explicit portable/native boundary crossings,
- standalone family package hosting/publishing does **not** happen from this repo.

The role of `reflaxe.std` is:

- give portable code an idiomatic shared authoring surface,
- let backends map that surface to the best native representation available,
- keep portability intent explicit,
- and avoid forcing users to choose between portability and obvious native representation wins.

The role of `reflaxe.std` is **not**:

- to absorb `rust.*`,
- to blur portable vs native policy,
- or to grow opportunistically backend-by-backend inside `haxe.rust`.

## Current post-M30 performance posture

After the JSON boundary convergence tranche:

- JSON remains the only current evidence-backed future hotspot family,
- the first safe runtime-side JSON pass already cut the measured portable/metal JSON runtime ratios
  materially without changing the public contract,
- `hot_loop_inproc` is not reopened without new evidence,
- `bytes` is not an active standalone convergence milestone,
- `int64` stays a portability-cost tracker, not a near-native parity KPI.

That means the next justified optimization work, if any, should be:

- narrow,
- evidence-backed,
- semantics-preserving,
- and attached to a specific hotspot family rather than a broad "optimizer spree."

For JSON specifically, that means:

- keep working at the `hxrt::json` boundary and JSON-specific lowering points,
- do not use generic post-lowering clone-elision heuristics as a shortcut,
- and only remove portable overhead when the ownership proof is attached to the emitted JSON path
  itself.

## How to decide between `portable` and `metal`

Use this rule of thumb:

1. Start with `portable`.
2. Stay in `portable` if the code is already compiling to native-feeling Rust shapes and the
   measured cost is acceptable.
3. Use `reflaxe.std` where it gives portable idioms that can still lower efficiently.
4. Move to `metal` when the **source contract** should become Rust-first, not merely because you
   hope the backend might optimize harder.

Practical signals that `metal` is justified:

- the source should use native Rust-facing surfaces directly,
- the team wants strict no-raw app boundaries by default,
- portability is no longer a meaningful goal for that module,
- or a measured hotspot still needs a Rust-first contract after portable-preserving optimizations
  are exhausted.

## Current evidence anchors

- Contracts and profile semantics: `docs/profiles.md`
- Rust-side `reflaxe.std` boundary: `docs/reflaxe-std-adoption-contract.md`
- Performance baselines and posture: `docs/perf-hxrt-overhead.md`
- JSON hotspot contract: `docs/json-boundary-contract.md`
- Release posture: `docs/semver-release-posture.md`
- Example entrypoints: `docs/examples-matrix.md`

## Bottom line

The target state is:

- portable code when you want portable semantics and shared abstractions,
- metal code when you want an explicitly Rust-first contract,
- and backend lowering quality strong enough that portable code does not pay unnecessary tax just
  for staying portable.

That is how `reflaxe.rust` can aim to be the best way to write production Rust short of writing
raw Rust directly, without cheating on the public contract model.
