# Pre-1.0 Compatibility Review

Status: compatibility classification for `haxe_rust-ykls.6`.

This review identifies the surfaces that could form a stable contract. It does not approve
`1.0.0`, widen the support matrix, or convert partial evidence into blanket parity.

## Classification meanings

| Class | Compatibility meaning |
| --- | --- |
| **Stable candidate** | Intended to keep its documented semantics and shape across a future stable major. Breaking changes would require the next major after graduation. |
| **Qualified stable candidate** | Supported only inside the named profile, platform, environment, or proof boundary. The qualification is part of the contract. |
| **Experimental** | Useful and tested, but still allowed to change during `0.x`; changes require release notes and migration guidance. It is not silently promoted by a `1.0` tag. |
| **Excluded/internal** | Implementation detail, reserved feature, unsupported expansion, or framework-only escape hatch. No direct application compatibility promise is made. |

“Stable candidate” remains provisional until a separate reviewed major-1 authorization names the
exact stable surface.

## Public contract classification

| Surface | Classification | Boundary that must remain visible |
| --- | --- | --- |
| `portable` profile and ordinary supported Haxe language/std behavior | **Stable candidate** | Haxe semantics are the contract. Evidence depth still comes from the feature matrix and semantic-confidence classes, not from inventory counts alone. |
| Portable `sys.*` | **Qualified stable candidate** | Linux is the full-CI platform. Windows and macOS are smoke lanes. HTTP has targeted proof; TLS and DB remain platform/environment-sensitive. |
| `metal` profile, strict app boundary, native-import diagnostics, and fallback reporting | **Stable candidate** | Rust-first semantics apply only where documented. `metal` is not a promise of automatic no-runtime output or arbitrary raw Rust authority. |
| `rust.Option`, `rust.Result`, `rust.Vec`, `rust.HashMap`, time/path values, iterator helpers, and documented tools | **Stable candidate for documented operations** | Missing trait ergonomics, borrowed-entry APIs, clone reductions, and broader no-hxrt support are not implied. |
| `rust.Ref`, `rust.MutRef`, `rust.Str`, `rust.Slice`, `rust.MutSlice`, scoped borrow/RAII callbacks | **Qualified stable candidate** | Lexical-region restrictions and current diagnostics are part of the contract. Unknown closure/helper side effects and richer field/static provenance remain excluded. |
| `rust.concurrent.*` and `rust.async.*` | **Qualified stable candidate** | Only the documented typed subset is included. Async is metal-only, uses a synchronous entry boundary, and is incompatible with `rust_no_hxrt`. |
| `rust.fs.NativeFiles`, `rust.process.*`, and `rust.net.*` | **Qualified stable candidate** | Only the documented direct-file, owned-command/narrow-child, and blocking-localhost TCP/UDP contracts are included. No DNS, arbitrary-host, live-stream, TLS, DB, shell, detached-process, or async-network promise is inferred. |
| `rust.serde.SerdeJson` | **Experimental** | Native JSON interop remains partial; there is no first-party typed schema/derive or documented no-hxrt JSON contract. |
| `rust.tui.*` and `rust.test.*` | **Experimental tooling** | These are valuable dogfood/example helpers, not the compiler’s general stable systems/UI contract. `TuiDemo` is explicitly a low-level backend. |
| `@:rustCargo`, `@:rustExtraSrc`, typed extern/`@:native` integration, and deterministic Cargo dependency merging | **Stable candidate** | Conflicts must keep failing closed. Application code should bind native islands through typed Haxe surfaces. |
| `@:haxeMetal`, `@:rustMetal` migration alias, contract/runtime/optimizer reports | **Stable candidate at the documented boundary** | Report schemas are versioned machine contracts; new fields may be additive. The old alias is compatibility-only and new code uses `@:haxeMetal`. |
| `@:rustImpl` body strings, `rust.metal.Code`, `@:rustAllowRaw`, and raw `__rust__` | **Experimental/framework escape hatches** | They must not become the normal application model. Metal-clean policy may reject them even when strict-boundary authority exists. |
| Reserved `@:rustNativeWrapper`, portable `rust_no_hxrt`, auto-profile selection, and unbundled future `reflaxe.std` modules | **Excluded/not shipped** | Reserved metadata is rejected today. Future admission requires its own typed contract, migration rules, and fixtures. |
| `hxrt`, `std/rust/native/*.rs`, generated private aliases/helpers, compiler passes, and internal AST/report builders | **Excluded/internal** | Public Haxe behavior and documented generated artifacts are the compatibility boundary; helper organization is not. Native helper manifest classifications govern implementation growth, not public SemVer by themselves. |

## Defines and metadata policy

The canonical inventory remains [Defines reference](defines-reference.md). Its compatibility groups
are:

- stable candidates: output/build controls, `reflaxe_rust_profile`, documented string defaults,
  Cargo controls, report switches, strictness controls, and `@:haxeMetal`;
- qualified stable candidates: `rust_async`, `rust_no_hxrt`, `rust_nested_modules`, native-import
  strictness, and explicit fallback/diagnostic controls under their documented constraints;
- migration-only: `@:rustMetal` and compiler errors for removed `rust_idiomatic`, `rust_metal`, and
  `rust_async_preview` selectors;
- debug/internal: debug tracing switches and repo-only example enforcement;
- excluded until separately admitted: reserved wrapper metadata and undocumented defines.

Adding a define is not enough to make it stable. It needs documentation, positive/negative fixtures,
and a named compatibility class here or in a successor review.

## Generated package and crate contract

Stable-candidate boundaries:

- real Git tags own published versions; checkout metadata remains a development sentinel;
- releases provide one deterministic Haxelib-shaped ZIP through GitHub Releases;
- the package installs through the documented lix/Haxelib flow;
- generated output is a Cargo 2021 crate with deterministic source/report files;
- default output may bundle `hxrt` when Haxe semantics require it;
- metal `rust_no_hxrt` omits the runtime only after source and emitted-output eligibility gates;
- nested module output is opt-in and retains documented root aliases for handwritten-Rust migration.

Private helper paths inside `hxrt` and compiler-generated implementation details are not public APIs.
Changing externally consumed generated module paths, report schemas, package layout, or Cargo behavior
requires migration evidence even when Haxe source still compiles.

## Platform and toolchain policy

Current `0.x` policy:

- Haxe is pinned to `4.3.7`;
- repository/release automation uses Node `22.14.0` under the declared package engine range;
- generated crates use Rust edition 2021;
- CI validates the current Rust stable toolchain rather than a fixed MSRV;
- Linux is the primary full-validation platform;
- Windows and macOS are curated smoke platforms, not blanket semantic-parity claims;
- cross-compilation through `rust_target` is supported as Cargo plumbing, not proof that every target
  triple or platform API is validated.

The rolling-stable Rust policy is honest for the current preview line, but it is not sufficient by
itself for a stable-major promise. Before major-1 authorization, the project must either select and
enforce an MSRV or adopt an equivalently reproducible pinned release-toolchain policy with an
explicit support/update window. The final stability decision owns that blocker; this review does
not invent an unsupported historical MSRV.

## Migration and deprecation rules

During `0.x`:

- intentional breaking changes require linked Beads evidence, release notes, and concrete migration
  steps;
- stable candidates should not be broken casually merely because SemVer permits `0.x` movement;
- experimental surfaces may change in a minor release, but never silently;
- excluded/internal surfaces carry no direct application compatibility promise.

For a future stable major:

- breaking a stable or qualified-stable surface requires a new major;
- deprecations name the replacement and migration path and remain available through at least one
  minor release; removal still waits for the next major;
- additive report-schema changes are permitted, but removing or changing existing machine fields is
  breaking unless a versioned parallel schema and migration window are provided;
- urgent security/correctness action may disable unsafe behavior sooner, but must ship an advisory,
  migration path, and explicit compatibility disposition;
- experimental features remain visibly experimental after `1.0` unless the major authorization
  explicitly promotes them.

## Known defers and graduation blockers

- Four correctly spaced weekly stability checkpoints have not yet elapsed.
- No stable Rust MSRV or equivalent pinned release-toolchain support window is selected.
- Borrow provenance beyond the documented local/scoped analysis remains partial.
- MainLoop/EntryPoint, TLS, DB, Windows, macOS, and broader network/process behavior retain their
  documented proof qualifications.
- Native JSON schema/derive, portable no-hxrt, generated native wrappers, broader trait/bound
  metadata, and general async networking are not stable-major commitments.

These are honest boundaries, not instructions to implement every deferred feature before `1.0`.
The final major scope may explicitly exclude or qualify them.

## Bun-class quality north star

The compiler should be capable in principle of supporting serious, performance-sensitive,
cross-platform systems software comparable in complexity to Bun. That is a quality criterion for
generic compiler behavior, typed native authority, output readability, performance, diagnostics,
and reproducibility. It is not a promise to build BunHx or a reason to add application-specific
lowering. A future BunHx may be a bounded pressure test; every finding must generalize into a reusable
compiler/runtime/facade contract.

## Decision

The current surface is coherent enough to enter the sustained stability review as an intentional
`0.x` production-capable preview. It is not yet authorized as `1.0`: elapsed weekly evidence and a
stable Rust toolchain policy remain outstanding, and the final reviewed major scope must preserve
the qualifications above.

## Related evidence

- [SemVer and release posture](semver-release-posture.md)
- [Feature support matrix](feature-support-matrix.md)
- [Metal type surface gap matrix](metal-type-surface-gap-matrix.md)
- [Systems and environment posture](systems-environment-posture.md)
- [Concurrency posture](concurrency-posture.md)
- [Weekly CI evidence](weekly-ci-evidence.md)
- [Production readiness](production-readiness.md)
