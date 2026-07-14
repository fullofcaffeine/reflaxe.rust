# Pre-1.0 Compatibility Review

Status: package-complete schema-v2 compatibility graph established by `haxe_rust-p6hs.2`;
stable-major admission remains a separate reviewed decision.

This review identifies the surfaces that could form a stable contract. It does not approve
`1.0.0`, widen the support matrix, or implicitly promote qualified and experimental surfaces. The
Rust toolchain policy is now enforced separately. The machine-readable source of truth is
[`public-compatibility-manifest.json`](public-compatibility-manifest.json); this page explains its
policy and records its generated summary.

The independent 2026-07-13 review confirmed that the four-class model is sound but found that the
first-generation manifest saw only names under `std/rust`. Schema v2 closes that structural gap. It
lexically inventories every importable declaration and public operation under the two source roots
that become the installed Haxelib class path: `src/reflaxe/rust` and `std`. It records normalized
type/member signatures, constructors, generic bounds/defaults, direct and transitive shipped-type
references, metadata/define grammar and defaults, lifecycle state, and validated evidence IDs.

This graph proves inventory and source-shape drift; it does not prove runtime correctness. No
`stable-candidate` or `qualified-stable-candidate` row is implicitly admitted. The remaining audit
Beads attach operation-specific semantic/failure/lifecycle evidence or move the affected operations
to experimental/internal before major-1 authorization. See the
[audit disposition](production-readiness-audit-2026-07-13.md).

## Exact compatibility classes

Every surface has exactly one class:

| Class | Compatibility meaning |
| --- | --- |
| `stable-candidate` | Proposed for admission to the next stable major. If admitted, its documented names and signatures, accepted input grammar and defaults, observable semantics, and specifically listed generated artifacts become SemVer-governed public API. A change is breaking when a conforming consumer inside the documented boundary stops compiling, building, parsing, or receives behavior contrary to that contract. Accidental behavior, known bugs, exact formatting, and unlisted implementation details are not protected. |
| `qualified-stable-candidate` | The same protection, but only inside an explicitly named profile, operating system, architecture, toolchain range, prerequisite, environment, or capability domain. Narrowing that domain or increasing its prerequisites is breaking after admission. Evidence depth is recorded separately; it is not itself the qualification. |
| `experimental` | A documented public surface intentionally excluded from stable-major SemVer until explicitly promoted. During `0.x`, and after `1.0` in a minor rather than patch release, it may change or be removed with release notes and practical migration guidance. A major-version tag never promotes it implicitly. |
| `excluded-internal` | Not public API: compiler implementation, private helper organization, reserved/rejected feature, or unsupported name. A callable documented escape hatch or migration alias cannot use this class merely because it is inconvenient to stabilize. |

`deprecated` is an orthogonal lifecycle status, not a fifth class. A deprecated stable surface
remains protected for the remainder of its current major. The manifest therefore records class,
admission (`candidate`, `admitted`, `experimental`, or `internal`), active/deprecated/reserved
status, qualification, protected contract units, evidence, and exclusions separately. An admitted
stable contract must name an authorization record and executable compile, generated-output,
semantic, policy, or release evidence; documentation or structural inventory alone cannot promote
it.

“Stable candidate” remains provisional until a later reviewed major-1 authorization names the
exact admitted surface.

## Machine-checked contract summary

<!-- BEGIN GENERATED PUBLIC COMPATIBILITY SUMMARY -->
| Contract | Class | Admission | Status | Qualification |
| --- | --- | --- | --- | --- |
| `portable-core` | `stable-candidate` | `candidate` | `active` | Only module/member behavior admitted by the versioned feature-support inventory; Haxe semantics are the oracle inside that set. |
| `portable-reflection-core` | `qualified-stable-candidate` | `candidate` | `active` | Only static class/enum names plus closed-world dynamic resolution, name lookup, and enum-constructor listing for public non-extern declarations known to the compilation. |
| `portable-call-stack-shape` | `qualified-stable-candidate` | `candidate` | `active` | The haxe.CallStack and StackItem API shape only; native frame capture and non-empty stack contents are not admitted. |
| `portable-mainloop` | `qualified-stable-candidate` | `candidate` | `active` | Only the target-side MainLoop and EntryPoint paths documented in the concurrency posture. |
| `portable-sys-core` | `qualified-stable-candidate` | `candidate` | `active` | Linux full CI plus the specifically documented Windows smoke operations; macOS is local-only evidence. |
| `portable-http` | `qualified-stable-candidate` | `candidate` | `active` | Documented local-server status, body, error, and callback behavior. |
| `portable-net-tcp` | `qualified-stable-candidate` | `candidate` | `active` | Targeted blocking TCP behavior on documented local-server lanes. |
| `portable-net-udp` | `qualified-stable-candidate` | `candidate` | `active` | Curated UDP smoke behavior only. |
| `portable-tls` | `qualified-stable-candidate` | `candidate` | `active` | Buildable TLS/SNI path; runtime behavior remains certificate-, network-, and environment-sensitive. |
| `portable-db-types` | `qualified-stable-candidate` | `candidate` | `active` | Shared DB interface/type shapes used by separately qualified drivers. |
| `portable-sqlite` | `qualified-stable-candidate` | `candidate` | `active` | In-memory SQLite runtime smoke boundary. |
| `portable-mysql-compile` | `qualified-stable-candidate` | `candidate` | `active` | Dependency and generated-code compile contract only. |
| `rust-values-core` | `stable-candidate` | `candidate` | `active` | Documented Option, Result, and tool operations only. |
| `rust-values-qualified` | `qualified-stable-candidate` | `candidate` | `active` | Only individually documented operations; gaps in traits, borrowed entries, cloning, strings, OsString, and iteration remain visible. |
| `rust-borrows` | `qualified-stable-candidate` | `candidate` | `active` | Documented lexical borrow regions, slice/string views, and scoped callbacks. |
| `rust-hxref` | `qualified-stable-candidate` | `candidate` | `active` | Opaque shared Haxe-reference handle for APIs that expose rust.HxRef<T>; strong cycles are not tracing-collected, and thread crossing depends on the owning API and payload bounds. |
| `rust-concurrency` | `qualified-stable-candidate` | `candidate` | `active` | Metal plus hxrt typed handle/value/scoped-callback subset; callbacks retain the Rust guard, and every same-handle operation throws HXRT-LOCK-REENTRANCY before acquisition. |
| `rust-async` | `qualified-stable-candidate` | `candidate` | `active` | Metal plus rust_async plus hxrt; synchronous main boundary. |
| `rust-systems` | `qualified-stable-candidate` | `candidate` | `active` | Documented direct file, owned command/narrow child, and blocking localhost socket operations. |
| `rust-prelude` | `qualified-stable-candidate` | `candidate` | `active` | Metal-only import hub; exported alias module path is protected. |
| `public-experimental` | `experimental` | `experimental` | `active` | Public preview/tooling surface excluded from stable-major admission until explicitly promoted. |
| `raw-experimental` | `experimental` | `experimental` | `active` | Controlled raw/stringly Rust authority under strict boundary rules. |
| `internal-helper` | `excluded-internal` | `internal` | `active` | Compiler/framework implementation only; application imports are unsupported and must be sealed by the helper-boundary guard. |
| `metal-profile` | `stable-candidate` | `candidate` | `active` | Profile selection, strict app boundary, native-import policy, and documented fallback/report behavior only. |
| `metadata-stable` | `stable-candidate` | `candidate` | `active` | Only the explicitly listed form and placement grammar. |
| `metadata-qualified` | `qualified-stable-candidate` | `candidate` | `active` | Only the form and environment named by each metadata entry. |
| `metadata-experimental` | `experimental` | `experimental` | `active` | Stringly or advanced metadata excluded from stable admission. |
| `haxe-metal-alias` | `stable-candidate` | `candidate` | `deprecated` | Deprecated compatibility alias for rustMetal. |
| `metadata-reserved` | `excluded-internal` | `internal` | `reserved` | Rejected or compiler-owned metadata. |
| `build-controls` | `stable-candidate` | `candidate` | `active` | Documented normal output/build/profile/report and structured Cargo controls. |
| `build-qualified` | `qualified-stable-candidate` | `candidate` | `active` | Only the documented profile, runtime, module topology, target, or source-ownership domain. |
| `build-experimental` | `experimental` | `experimental` | `active` | Escape, raw passthrough, runtime-feature, or preview control. |
| `build-internal` | `excluded-internal` | `internal` | `active` | Repository enforcement, debug, deprecated/rejected selector, or compiler bootstrap detail. |
| `report-json` | `qualified-stable-candidate` | `candidate` | `active` | Machine-readable JSON only; consumers must ignore unknown fields. Versioned schemas and compatibility baselines protect the admitted shape. |
| `diagnostic-identifiers` | `stable-candidate` | `candidate` | `active` | Only identifiers explicitly listed in the diagnostic registry; unlisted compiler diagnostics are not admitted. |
| `generated-crate` | `qualified-stable-candidate` | `candidate` | `active` | Documented default, nested, no-hxrt, custom-Cargo, extra-source, and cargo-execution boundaries. |
| `generated-package` | `stable-candidate` | `candidate` | `active` | Published Haxelib-shaped package and installed-package workflow. |
| `generated-private` | `excluded-internal` | `internal` | `active` | Generated helper/wrapper details not admitted as consumer API. |

Inventory: 318 shipped Haxe types, 1541 public operations, 18 metadata names, 55 defines, 4 JSON reports, 6 generated-artifact contracts, and 33 validated evidence records.
<!-- END GENERATED PUBLIC COMPATIBILITY SUMMARY -->

The guard enumerates no-package overrides, primary and secondary module types, direct `std/**`
bridges, importable `hxrt.*` implementation declarations, and shipped compiler declarations.
Compiler/runtime helpers are explicitly classified `excluded-internal`; their presence in the
package does not make them stable API. Bead `haxe_rust-p6hs.3` sealed those namespaces while keeping
the documented injection shim as an explicit public experimental exception. A new,
removed, duplicated, or unclassified type or operation; a changed signature/default/generic bound;
a changed transitive shipped type; an unknown metadata/define grammar; a missing evidence target;
or an invalid promotion/deprecation state fails CI.

The scanner deliberately protects Haxe declaration shape rather than function bodies or generated
Rust formatting. It runs without loading one conditional Haxe compilation, so all shipped lexical
declarations are visible. Haxe typing plus semantic/failure fixtures remain the authority for
behavior. After intentional public declaration changes, run
`npm run docs:compatibility:refresh`, review the generated manifest diff, and attach migration and
evidence changes in the same Bead.

## Important surface decisions

The portable contract is the versioned admitted module/member inventory, not the circular phrase
“ordinary supported Haxe.” Haxe semantics remain the oracle inside that admitted set. Inventory
closure alone is not runtime-semantic closure.

The `metal` stable candidate covers profile selection, strict-boundary enforcement, native-import
policy, and documented fallback/report behavior. It does not cause every `rust.*`, no-hxrt, raw,
trait, async, or systems feature used in a metal compilation to inherit stable status.

`rust.Option`, `rust.Result`, and their documented tools are the strongest stable-value candidates.
Vec, HashMap, path/time/string/OsString/iterator values and tools remain qualified to individually
documented operations. Borrow and slice APIs are qualified to their lexical-region contract.

`rust.HxRef<T>` is admitted only as an opaque qualified handle because concurrency and async APIs
expose it directly. Its current `Arc<HxCell<T>>`/lock representation, layout, and internal methods
are explicitly non-contractual. Its protected behavior is nullability, shared identity, alias-visible
mutation, and deterministic release of acyclic payloads after the last owner. Strong cycles are not
tracing-collected and require an explicit break point; thread crossing remains qualified by the
owning API and payload bounds in [the HxRef lifecycle contract](hxref-lifecycle.md).

`rust.serde.SerdeJson`, `rust.tui.*`, `rust.test.*`, and
`rust.adapters.ReflaxeStdAdapters` remain experimental. Compiler-owned `@:rustTest` is a separate
stable metadata candidate. Marker-only `@:rustImpl("Trait")` is qualified to local emitted types;
body-string and object/`forType` forms remain experimental raw authority. `@:rustDerive`,
`@:rustMutating`, and `@:rustReturn` are experimental. `rust.metal.Prelude` is a qualified stable
import hub. `@:rustMetal` is the canonical stable metadata candidate. `@:haxeMetal` remains a
deprecated stable-candidate compatibility alias; if the alias is admitted into major 1, it cannot
be removed before major 2.

Raw `rust.metal.Code`, `@:rustAllowRaw`, `__rust__`, and the injection macro shim are public
experimental escape hatches. They are not universally framework-only: a narrowly authorized
project class may use them under the documented strict and metal-clean rules.

Native-helper manifest classifications are implementation-lifecycle labels, not public SemVer
classes. A helper file, class, module path, or implementation may change without a public break
when the admitted facade and explicitly listed generated artifacts remain compatible. Conversely,
a stable facade remains protected whether implemented by lowering, a native helper, or `hxrt`.
The package-wide helper boundary is now enforced from one compiler-owned namespace policy:
`haxe.BoundaryTypes.*`, `hxrt.*`, `reflaxe.rust.*`, and `rust._internal.*` are implementation-only
for application source. Direct imports and fully qualified references fail with
`HXRS-INTERNAL-HELPER-IMPORT`; followed/transitive helper types behind a public facade remain legal.
The exact `reflaxe.rust.macros.RustInjection` path is an explicit `raw-experimental` exception,
not an accidental hole in the namespace rule.

## Defines and metadata

The manifest, not the prose-only Defines reference, is the canonical compatibility inventory. It
includes indirect controls such as `async_tokio_adapter` and the three `rust_hxrt_*` controls.

- normal output/build/report controls and structured object `@:rustCargo` are stable candidates;
- `rust_async`, `rust_no_hxrt`, `rust_nested_modules`, and target/source ownership controls are
  qualified candidates;
- unresolved-monomorph/core-type escapes, metal fallback, `rust_hxrt_*`,
  `async_tokio_adapter`, raw Cargo/dependency passthroughs, and `rust_emit_upstream_std` are
  experimental;
- debug, repository-only enforcement, and removed selector controls are excluded/internal;
- raw `rust_cargo_toml` may promise literal copy/substitution only if that precise ownership rule is
  later admitted; the resulting manifest remains consumer-owned.

Each metadata entry records accepted forms separately when one name spans contracts. In particular,
structured `@:rustCargo` does not stabilize its raw-string form, and marker-only `@:rustImpl` does
not stabilize body-string/object forms.

## Reports and generated artifacts

The four machine-readable report families are:

| JSON artifact | Current schema |
| --- | ---: |
| `metal_report.json` | 1 |
| `contract_report.json` | 6 |
| `runtime_plan.json` | 4 |
| `optimizer_plan.json` | 2 |

The enforced contract protects each filename, `schemaVersion`, required existing field names and
types, documented stable reason/category identifiers, field meaning, and any ordering explicitly
promised to consumers. Consumers must ignore unknown fields, after which new optional fields may be
additive. A schema increment does not authorize replacing an admitted filename incompatibly: use a
parallel versioned artifact plus migration window, or a new major. Markdown reports are human-facing
and not machine-parseable contracts. The versioned schemas, compatibility baseline, and generated
crate/package boundaries are documented in
[`generated-consumer-contract.md`](generated-consumer-contract.md).

The generated-crate candidate explicitly covers `Cargo.toml` and `src/main.rs` roots, binary-crate
default, edition 2021, crate-name override, conditional `./hxrt` subtree/dependency, `rust_no_hxrt`
omission, extra-source discovery/copy/module inclusion, structured dependency merge/conflict,
Cargo subcommand/flags and non-zero exit propagation, nested source paths and root aliases,
custom-Cargo ownership, and report filenames. The generated `__hx_tests` wrapper name/layout is
private for now.

Exact whitespace, rustfmt output, temporary ordering, private generated helper names, native-helper
module paths, internal `hxrt` structure, and the checkout development-version literal are not
protected.

The package candidate protects a deterministic Haxelib-shaped ZIP, install through Haxelib/lix and
`-lib reflaxe.rust`, staged `src/**/*.cross.hx` transformation, required compiler/`runtime/`/`vendor/`
roots, staged version/provenance metadata, safe archive paths, and the documented source-checkout
versus installed-package classpath behavior.

Changing an admitted generated module path, report schema, package layout, or Cargo behavior is a
breaking change after stable admission unless its documented additive/parallel-version rule applies.
Migration evidence is required but cannot turn an incompatible change into a non-breaking one.

## Platform and toolchain policy

- Haxe is pinned to `4.3.7`.
- Repository/release automation uses Node `22.14.0` under the declared engine range.
- Generated crates use Rust edition 2021.
- Generated crates require Rust `1.96.0` or newer, and exact-minimum CI validates that floor.
- `rust-toolchain.toml` defaults repository work to the exact minimum. Release automation
  explicitly activates its reviewed patch toolchain, and a separate required lane validates
  rolling current stable.
- Linux is the primary full-validation CI platform.
- Windows has a curated smoke-CI lane.
- macOS currently has local contributor validation only and is not a CI-backed support lane.
- None of those statements implies blanket cross-platform semantic parity.
- `rust_target` is Cargo plumbing, not proof for every target triple or platform API.

The complete support and floor-update contract is
[`rust-toolchain-policy.md`](rust-toolchain-policy.md). It does not claim support for any historical
Rust version below the tested floor.

## Migration and deprecation rules

During `0.x`, intentional breaks require Beads evidence, release notes, and concrete migration.
Stable candidates should not be broken casually. Experimental changes/removals occur in a minor,
not patch, release and include practical guidance.

After stable admission:

- stable and qualified-stable breaks require a new major;
- narrowing a qualified domain or adding prerequisites is breaking;
- changing defaults, accepted metadata grammar, profile semantics, module paths, required Cargo
  dependencies, Cargo edition, platform floor, or toolchain floor is breaking unless an admitted
  update policy expressly permits it;
- adding enum constructors or sealed cases is not automatically additive when consumers may switch
  exhaustively;
- stable diagnostics protect an identifier/category, severity, and trigger—not exact English prose;
- a fix demonstrably restoring the written contract may be corrective, with release notes when
  existing consumers could be affected;
- security exceptions use the least disruptive safe change and record an explicit compatibility
  disposition;
- a deprecated stable surface and documented replacement coexist for the rest of the current major;
  removal occurs no earlier than the next major;
- migration aliases state introduction, deprecation, replacement, and earliest-removal major.

Admitted profile, async/no-hxrt, borrow-region, native-import, structured-metadata, and Cargo
failures now use the typed `HXRS-*` registry in
[`diagnostic-contract.json`](diagnostic-contract.json). Their identifier, severity, and documented
trigger are protected contract units; exact diagnostic prose and Haxe's source-position formatting
remain free to improve. Diagnostics outside that explicit registry remain unadmitted.

## Known defers and decision

The former fixed-count calendar checkpoint gate was superseded by materially distinct event
evidence. Weekly runs continue as monitoring, but elapsed Mondays are not a proxy for compatibility.
Broader borrow provenance, platform parity, TLS/DB/network breadth, typed
derive/where/associated-type work, portable no-hxrt, and generated native wrappers may remain
explicitly qualified, experimental, or excluded rather than being rushed into scope.

The surface is coherently classified for continued `0.x` releases. Classification and event
evidence still do not authorize `1.0.0`; a separate reviewed per-major approval must name the exact
stable contract when the remaining substantive evidence warrants it.

## Bun-class quality north star

The compiler should be capable in principle of supporting serious, performance-sensitive,
cross-platform systems software comparable in complexity to Bun. This is a pressure test against
declared supported lanes; it does not expand the support matrix or imply a BunHx delivery
commitment. Findings must generalize into reusable compiler/runtime/facade behavior rather than
application-specific lowering.

## Related evidence

- [SemVer and release posture](semver-release-posture.md)
- [Feature support matrix](feature-support-matrix.md)
- [Metal type surface gap matrix](metal-type-surface-gap-matrix.md)
- [Systems and environment posture](systems-environment-posture.md)
- [Concurrency posture](concurrency-posture.md)
- [Weekly CI evidence](weekly-ci-evidence.md)
- [Production readiness](production-readiness.md)
