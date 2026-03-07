# Spike: `reflaxe.std` Cross-Repo Handoff

Date: 2026-03-06  
Scope bead: `haxe.rust-oo3.18.6`

## Why this exists

`reflaxe.rust` now has the first concrete adoption slice for the shared portable idiom layer:

- Rust-side contract docs,
- contract-first fixtures for portable `Option` / `Result`,
- direct lowering to native Rust `Option` / `Result`,
- typed migration adapters,
- deterministic report artifacts carrying family pin metadata.

That work is intentionally only the Rust adoption slice. The shared package model is larger than
this repo and needs explicit ownership so the roadmap stays honest about what belongs here versus
what belongs in sibling repos.

## Two-layer package model

The current family direction is:

1. `reflaxe.family.std`
   - governance/spec/conformance package
   - owns portable semantics, allowlists, fixture mapping, provenance, and version pinning
2. `reflaxe.std`
   - user-facing portable idiom package
   - starts with `Option<T>` / `Result<T, E>` in v1
   - is expected to grow over time into a broader portable idiom layer

Important constraint:

- `reflaxe.std` is not "portable `rust.*`".
- Backend-native facades stay backend-local (`rust.*`, `go.*`, `elixir.*`, etc.).
- Any bridge between portable and native surfaces must stay explicit.

## Scope split by repo

### `haxe.rust`

Status: implemented for the initial adoption slice.

Rust owns:

- proving that portable idioms can lower to native Rust representations without wrapper tax when
  semantics line up,
- documenting the portable/native boundary clearly,
- keeping portable contract reports deterministic,
- contributing fixture evidence back into the family contract.

Rust does **not** own:

- hosting the canonical standalone `reflaxe.std` package release,
- defining non-Rust-native backend mappings,
- formalizing Elixir lane semantics,
- defining JS/TS consumer-shape policy for non-Rust generators.

### `haxe.go`

Status: intended host / reference implementation for the family split.

Go is the expected host for:

- extracting and publishing the shared package boundary cleanly,
- keeping `reflaxe.family.std` as the governance/spec package,
- publishing the first standalone `reflaxe.std` package shape,
- defining cross-repo rollout/pin/update workflow.

Go-specific rule that Rust depends on:

- portable `reflaxe.std.Result` must remain distinct from native `go.Result` rather than silently
  lowering to `(T, error)`-style semantics.

### `haxe.elixir`

Status: blocked on explicit contract formalization.

Elixir needs root-cause work before it can be considered a clean adopter:

- explicit portable vs native lane selection,
- real `Option` lowering/transform support,
- explicit adapters for BEAM-native idioms (`{:ok, v}`, `{:error, e}`, `nil`) without silent
  semantic mode switching.

Rust depends on Elixir only for cross-family convergence, not for local correctness.

### `haxe` JS target

Status: consumer/reference, not host.

Core Haxe JS is expected to consume the portable `reflaxe.std` API using existing enum lowering.
The important work there is fixture coverage and documentation, not a new semantics host.

### `genes-ts`

Status: consumer adapter target.

`genes-ts` should consume the portable layer and document the emitted JS/TS shape explicitly
(notably enum discriminator configuration), but it should not become the family contract host.

## Rust-local completion criteria for this handoff

Rust can consider the cross-repo handoff done when:

1. Rust docs explicitly state what is implemented locally and what is external ownership.
2. Rust docs make the package layering clear:
   - `reflaxe.family.std` = governance
   - `reflaxe.std` = user-facing portable idiom package
3. Rust docs make the v1 scope clear:
   - `Option` / `Result` are the first slice, not the whole long-term package ambition.
4. The roadmap no longer implies that Rust alone is responsible for publishing the family package.

## Current blockers outside this repo

- `haxe.go`: publish/host the standalone package boundary and family rollout workflow
- `haxe.elixir`: formal portable/native contract lanes + real `Option` transform support
- `haxe` / JS consumer path: fixture/docs confirmation for portable enum shape
- `genes-ts`: stable JS/TS consumer docs and golden fixtures for portable enum shape

## Rust-side conclusion

Rust is on the correct path for the family model:

- keep explicit `portable|metal` contracts,
- allow portable abstractions to lower to native Rust representations when semantics match,
- keep native imports explicit,
- treat `reflaxe.std` as a broader portable idiom layer in the long term,
- keep v1 deliberately narrow enough to stabilize semantics before broadening the API surface.
