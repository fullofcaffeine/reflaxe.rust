# `reflaxe.std` Package Extraction Tracker

Status as of 2026-07-09:

- `haxe.rust` admits and lowers supplied `reflaxe.std.Option` / `reflaxe.std.Result` modules.
- `haxe.rust` does not ship the canonical `reflaxe.std` Haxe module definitions.
- Canonical `reflaxe.std` module ownership is assigned outside `haxe.rust`, in the standalone
  family package lane coordinated from the Go/family extraction work.
- Public Rust docs must not tell app authors to depend on `reflaxe.std` by default until the
  standalone package, install flow, adapters, and conformance fixtures exist.

## Why This Exists

Rust already proves the first useful portable-idiom slice: portable `Option` / `Result` source can
lower to native Rust `Option` / `Result` representations when those modules are supplied on the
classpath. That is compiler admission and backend lowering, not package hosting.

This tracker keeps four things separate:

1. `reflaxe.family.std`: governance, specs, allowlists, provenance, and conformance artifacts.
2. `reflaxe.std`: the future user-facing portable idiom package.
3. backend-native surfaces such as `rust.*`, `go.*`, `ocaml.*`, and Ruby/Rails facades.
4. fixture-local modules used to prove Rust lowering before the shared package exists.

## Ownership Matrix

| Repo | Current state | Owns for this rollout | Must not claim |
| --- | --- | --- | --- |
| `haxe.rust` | Compiler admission, fixtures, native Rust lowering, typed Rust adapters, and report/family-pin evidence exist for supplied `reflaxe.std.Option` / `reflaxe.std.Result` modules. | Rust lowering quality, Rust contract reports, Rust adapter docs, and honest public wording. | Hosting or publishing the standalone `reflaxe.std` source package. |
| `haxe.go` | Existing docs track `reflaxe.family.std` extraction and sibling rollout gates; current app-facing result surface is backend-local `go.Result<T>`. | Initial family extraction coordination and the first standalone package-shape plan, while keeping `go.Result<T>` backend-local. | Treating `go.Result<T>` as portable `reflaxe.std.Result<T, E>` or silently mapping portable result semantics to Go `(T, error)` semantics. |
| `haxe.ocaml` / `reflaxe.ocaml` | OCaml docs expose backend-native `ocaml.Option<T>` and `ocaml.Result<T, E>` and document Reflaxe `_std` source/package layout. | Future adopter/reference for explicit adapters once the shared package exists. | Publishing the canonical portable `reflaxe.std` package from the OCaml backend or replacing native OCaml surfaces silently. |
| `haxe.ruby` | Ruby docs focus Ruby/Rails facades, gem-layer companion packages, and `_std` package flattening; no active `reflaxe.std` Option/Result host is documented. | Future adopter only if Ruby-native idiom surfaces need typed adapters after package publication. | Treating Rails/Ruby companion packages as the portable `reflaxe.std` package. |
| Haxe JS / `genes-ts` consumers | Expected consumers of the portable API once it exists. | Consumer-shape fixtures and JS/TS emission docs. | Becoming the family package host or redefining portable semantics through emitter-specific enum shape. |

## V1 Portable API Boundary

The first `reflaxe.std` user-facing package slice is intentionally narrow:

- `Option<T>` with `Some` / `None`.
- `Result<T, E>` with `Ok` / `Err`.
- Small tool or extension modules such as `OptionTools` / `ResultTools`.

Out of v1:

- a public `Outcome<T, E>` alias surface;
- portable collection facades;
- backend-native APIs under the `reflaxe.std` namespace;
- silent substitution of `rust.*`, `go.*`, `ocaml.*`, Ruby/Rails, or JS-specific APIs.

Future surfaces require a per-surface admission record that names portable semantics, backend
representations, adapters, no-runtime eligibility, conformance fixtures, and migration guidance.

## Migration And Adapter Contract

Existing consumers remain valid:

- Haxe-portable code can keep using upstream `haxe.*` / `sys.*` surfaces.
- Rust-native code can keep using `rust.Option`, `rust.Result`, and other `rust.*` surfaces.
- Go-native code can keep using `go.Result<T>` and Go metadata such as `@:go.valueError`.
- OCaml-native code can keep using `ocaml.Option<T>` and `ocaml.Result<T, E>`.
- Ruby/Rails code can keep using Ruby/Rails-specific facades and companion packages.

Migration to `reflaxe.std` must be opt-in until the package exists. Any bridge between portable and
native surfaces must be explicit and typed:

- Rust bridge today: `rust.adapters.ReflaxeStdAdapters`.
- Go, OCaml, Ruby, JS, and TS bridges are future package-adopter work and must choose local names
  that make the portable/native boundary visible.

No existing `haxe.*`, `rust.*`, `go.*`, `ocaml.*`, or Ruby/Rails public surface should be deprecated
only because `reflaxe.std` exists. Deprecation requires published package modules, migration notes,
adapter coverage, and CI evidence.

## Public Guidance Gate

Allowed wording today:

- "Rust admits and lowers supplied `reflaxe.std.Option` / `reflaxe.std.Result` modules."
- "Use `reflaxe.std` when the shared package is on your classpath."
- "The standalone package is external family work, not bundled by `reflaxe.rust`."

Forbidden wording today:

- "Install `reflaxe.rust` and import `reflaxe.std.Option`."
- "`reflaxe.std` is the default app-authoring recommendation."
- "`reflaxe.std` is a Rust-only wrapper over `rust.*`."
- "Any `reflaxe.std.*` module is admitted for native lowering by name alone."

Before public docs recommend `reflaxe.std` by default, all of these must exist:

1. Standalone package metadata for `reflaxe.std`.
2. Lix/haxelib install documentation for app authors.
3. Canonical Haxe module definitions for `Option` / `Result` and v1 helper modules.
4. Shared conformance fixtures for v1 semantics.
5. Backend adopter documentation for Rust, Go, OCaml, Ruby, and JS/TS consumer shape.
6. Typed adapter docs for native-to-portable and portable-to-native crossings.
7. A package smoke that proves an installed package works without fixture-local modules.
8. Version pin and update workflow tied back to `reflaxe.family.std` governance artifacts.

## Current Blockers

- The standalone `reflaxe.std` package repository/package shape is not yet published.
- `haxe.go` family extraction work still needs to turn the package plan into a releaseable artifact.
- OCaml, Ruby, JS, and TS consumer/adopter docs need package-specific adapter decisions after the
  package exists.
- Shared conformance fixtures need to move from Rust-local proof into package-owned validation.

## Rust-Side Closure Rule

Rust-side work for this tracker is complete when Rust docs:

- assign canonical `reflaxe.std` module ownership outside `haxe.rust`;
- keep `reflaxe.family.std` governance separate from user-facing `reflaxe.std`;
- specify migration/adapters without breaking existing portable or native consumers;
- gate public default-use guidance on package install and conformance evidence.

This document is that Rust-side tracker. It does not close the external package extraction work.
