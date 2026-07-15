# Architecture Capability Claims

This page is generated deterministically from [`architecture-capability-manifest.json`](architecture-capability-manifest.json).

## Why

The old Haxe-to-Rust impossibility argument combines several different questions: whether a tracing GC is mandatory, whether portable Haxe references can coexist with Rust ownership, whether Rust interop must cross a runtime, and whether Haxe must reproduce Rust lifetime syntax. Each exact claim needs its own evidence and boundary.

## What

The implemented architecture disproves the old claim that a usable Haxe-to-Rust backend is impossible without either a tracing GC or lifetime annotations everywhere, but the evidence still supports bounded, qualified claims rather than universal parity.

Current classification: **3 closed**, **7 qualified**, and **1 open**.

A closed status proves only the exact claim stated below. Qualified means the mechanism works inside explicit exclusions. Open means the public statement is blocked even if narrower components already work.

## How

- Existing compatibility, semantic-confidence, lifecycle, policy, output, performance, and consumer evidence stays owned by its current contract.
- This manifest references those authorities instead of duplicating their operation lists, counts, or current CI results.
- Status changes fail closed unless the claim retains the evidence and ownership required for its new classification.
- README and FAQ carry generated summaries, so their headline cannot drift independently.

## What You Can Say Today

> We have a working Haxe-to-Rust compiler with two explicit contracts: portable Haxe semantics use targeted Rust-owned runtime representations where semantics require them, while metal can expose typed Rust-native and fail-closed no-hxrt paths. Scoped borrows and small lifetime islands cover useful Rust interop without turning ordinary Haxe into lifetime-annotated pseudo-Rust.

Do not claim: The compiler has solved every Haxe-to-Rust program, automatically collects every cyclic object graph, reproduces Rust's complete borrow checker in Haxe, supports every lifetime-heavy crate directly, or always emits code equal to expert hand-written Rust.

Upgrade gate: Close the typed Rust IR, representation planning, borrow provenance and diagnostic mapping, real-crate interop, admitted std semantics, class-heavy cost, workload performance, and cyclic-graph decision tracks, then complete the independent claim review in haxe.rust-oo3.98.10.

Release boundary: This capability roadmap is separate from stable-major authorization. A claim can become stronger here without silently adding every related API or platform to the 1.x compatibility promise.

This manifest **does not authorize stable 1.0** and is independent from the stable-major release gate.

## Original Objection Map

| Objection | Current disposition | Owning claims |
| --- | --- | --- |
| A useful Haxe-to-Rust compiler must implement a tracing GC, losing Rust's benefits. | **Refuted as a necessity; broad closure open** | `memory.no-universal-tracing-gc`, `memory.portable-reference-semantics`, `runtime.fail-closed-no-hxrt`, `maturity.bounded-production`, `maturity.unqualified-objection-closure` |
| Rust libraries and externs must cross a universal GC/runtime representation and will therefore be janky. | **Refuted as a necessity; broad closure open** | `runtime.fail-closed-no-hxrt`, `interop.lifetime-islands`, `interop.typed-rust-crates`, `output.handwritten-rust-quality`, `maturity.bounded-production`, `maturity.unqualified-objection-closure` |
| The Haxe compiler must reproduce Rust's exact borrow checker before it can emit safe Rust. | **Refuted as a necessity; broad closure open** | `ownership.no-duplicate-rust-borrow-checker`, `ownership.scoped-borrow-safety`, `interop.lifetime-islands`, `maturity.bounded-production`, `maturity.unqualified-objection-closure` |
| Haxe source and a replacement stdlib need Rust lifetime annotations everywhere, so the result is no longer Haxe. | **Refuted as a necessity; broad closure open** | `ownership.no-duplicate-rust-borrow-checker`, `interop.lifetime-islands`, `interop.typed-rust-crates`, `stdlib.portable-contract`, `output.handwritten-rust-quality`, `maturity.bounded-production`, `maturity.unqualified-objection-closure` |

## Claim Review

### memory.no-universal-tracing-gc

- Status: **Closed**
- Question: Does compiling useful Haxe to Rust require an always-on tracing garbage collector?
- Verdict: No. The backend uses ordinary Rust-owned values where possible and explicit reference/runtime representations only where the selected Haxe contract needs identity, aliasing, nullability, mutation, dynamic behavior, exceptions, or platform state.
- Maps objections: `gc-required`
- Mechanisms:
  - Scalar, enum, owned metal, and admitted portable value paths lower to ordinary Rust values.
  - Portable Haxe reference identity is isolated behind opaque HxRef handles rather than a universal tracer.
  - Metal no-hxrt builds prove that selected Rust-first programs omit the semantic runtime entirely.
- Concrete counterexamples to the impossibility argument:
  - The metal_no_hxrt_minimal fixture Cargo-builds with no hxrt dependency, copied runtime crate, or hxrt path in emitted Rust.
  - HxRef lifecycle tests use Rust Drop and weak observers, not a tracing collector, for admitted acyclic payload cleanup.
- Evidence:
  - `test:hxref-lifecycle` (executable): Rust Drop counters and weak observers prove alias-visible identity and deterministic cleanup for admitted acyclic HxRef payloads while preserving the explicit strong-cycle boundary.
  - `test:metal-policy` (executable): Positive and negative compiler fixtures exercise fail-closed no-hxrt eligibility, emitted-runtime rejection, scoped borrow escape checks, overlap checks, typed native facades, and warning-clean Cargo builds.
  - `test:full-harness` (executable): The repository harness composes snapshots, semantic oracles, lifecycle, toolchain, report, diagnostics, metal policy, package/template, examples, and native parity gates.
- Qualifications: none for this exact narrow claim.
- Does not mean:
  - Portable reference-heavy programs have zero runtime or synchronization cost.
  - Strong HxRef cycles are automatically reclaimed.
  - Every Haxe value can be represented as an unboxed Rust value without changing Haxe semantics.
- Owner Beads: `haxe.rust-oo3.98.1`
- Blocking Beads: none
- Remaining-gap Beads: `haxe.rust-oo3.98.9`

### memory.portable-reference-semantics

- Status: **Qualified**
- Question: Can portable Haxe references preserve observable Haxe behavior without a tracing GC?
- Verdict: Yes for the admitted acyclic lifecycle, alias-visible identity, nullability, mutation, and documented crossing contracts. The current opaque HxRef implementation uses Rust shared ownership and interior mutability; strong cycles remain retained until explicitly broken.
- Maps objections: `gc-required`
- Mechanisms:
  - HxRef protects shared identity, alias-visible mutation, nullable reference defaults, and deterministic acyclic cleanup.
  - Typed semantic fixtures compare reference behavior between Haxe and generated Rust.
  - The representation is not public API, allowing future planner-driven owned or single-thread specializations when semantics prove them safe.
- Concrete counterexamples to the impossibility argument:
  - Class assignment and mutation can preserve Haxe aliases through reference-counted Rust primitives without tracing the entire heap.
  - Weak-observer lifecycle tests distinguish deterministic acyclic release from intentionally retained strong cycles.
- Evidence:
  - `test:hxref-lifecycle` (executable): Rust Drop counters and weak observers prove alias-visible identity and deterministic cleanup for admitted acyclic HxRef payloads while preserving the explicit strong-cycle boundary.
  - `test:semantic-differential` (executable): Haxe and generated Rust are compared on curated semantic oracles; the generated confidence report separately classifies semantic, compile-inventory, and smoke-only proof.
  - `test:hxrt-performance` (executable): The benchmark protocol tracks size, startup, throughput, and selected output-shape counters, including a metal no-hxrt lower-bound signal.
- Qualifications:
  - Strong HxRef cycles are retained; applications currently need explicit cycle breaking or a Rust-shaped graph model.
  - The current portable class path can pay Arc, lock, clone, allocation, and broad generic-bound costs that are not yet proved on class-heavy workloads.
  - Send, Sync, and static requirements are proven at known crossings but the representation/crossing plan is not yet the single source for every emitted bound.
- Does not mean:
  - The current Arc/RwLock representation is part of the public API.
  - Cyclic graph behavior is silently equivalent to tracing-GC Haxe targets.
  - Reference-heavy portable code already matches hand-written Rust cost on every workload.
- Owner Beads: `haxe.rust-oo3.98.3`, `haxe.rust-oo3.98.4`, `haxe.rust-oo3.98.9`
- Blocking Beads: none
- Remaining-gap Beads: `haxe.rust-oo3.98.3`, `haxe.rust-oo3.98.4`, `haxe.rust-oo3.98.9`

### runtime.fail-closed-no-hxrt

- Status: **Closed**
- Question: Can Rust-first Haxe code interoperate without carrying the Haxe semantic runtime?
- Verdict: Yes for the explicitly eligible metal subset. rust_no_hxrt omits hxrt and fails both before emission and after emission if typed semantics or generated Rust still require the runtime.
- Maps objections: `gc-required`, `runtime-interop-friction`
- Mechanisms:
  - NoHxrtEligibilityAnalyzer rejects known Dynamic, reflection, anonymous-object, nullable-string, async, and portable platform requirements.
  - The emitted-code guard rejects residual hxrt dependencies, copied runtime sources, and hxrt paths.
  - Typed rust.fs, rust.process, and rust.net facade fixtures own native Rust resources without a universal Haxe runtime boundary.
- Concrete counterexamples to the impossibility argument:
  - Minimal, owned command, file, TCP, and UDP metal fixtures Cargo-build with rust_no_hxrt.
  - Negative fixtures demonstrate that unsupported semantics fail with stable HXRS-NO-HXRT diagnostics rather than silently restoring hxrt.
- Evidence:
  - `test:metal-policy` (executable): Positive and negative compiler fixtures exercise fail-closed no-hxrt eligibility, emitted-runtime rejection, scoped borrow escape checks, overlap checks, typed native facades, and warning-clean Cargo builds.
  - `test:diagnostic-contract` (executable): The diagnostic registry and runtime fixture check keep borrow, no-hxrt, metadata, Cargo, dynamic, and reflection failures source-facing and versioned.
  - `contract:native-facades` (generated): Every shipped Rust helper island declares its Haxe owner, no-hxrt or hxrt-bridge contract, lowering rationale, dependencies, forbidden growth, evidence owner, and line budget.
  - `test:hxrt-performance` (executable): The benchmark protocol tracks size, startup, throughput, and selected output-shape counters, including a metal no-hxrt lower-bound signal.
- Qualifications: none for this exact narrow claim.
- Does not mean:
  - Portable Haxe compatibility can currently omit hxrt.
  - Every native crate shape is directly expressible through current Haxe types or metadata.
  - No-hxrt is a vague optimization switch; it is a strict metal contract.
- Owner Beads: `haxe.rust-oo3.98.1`
- Blocking Beads: none
- Remaining-gap Beads: `haxe.rust-oo3.98.6`

### ownership.no-duplicate-rust-borrow-checker

- Status: **Closed**
- Question: Must the Haxe compiler reproduce Rust's exact borrow checker and lifetime system?
- Verdict: No. The backend performs conservative source-level checks for compiler-created scoped borrow contracts, then emits Rust and leaves the complete Rust ownership and lifetime proof to rustc.
- Maps objections: `duplicate-borrow-checker`, `lifetime-annotated-source-and-stdlib`
- Mechanisms:
  - Typed borrow-region analysis diagnoses escapes and known mutable overlaps for rust.Ref, rust.MutRef, slices, and rust.Str tokens.
  - Owned derivations and sequential scoped borrows remain ordinary typed Haxe.
  - rustc remains the final authority for generated Rust and external crate lifetime relationships.
- Concrete counterexamples to the impossibility argument:
  - Positive scoped-borrow fixtures compile without Rust lifetime parameters in Haxe source.
  - Negative escape and overlap fixtures fail at the Haxe source boundary, while more complex lifetime constraints remain rustc's job.
- Evidence:
  - `test:metal-policy` (executable): Positive and negative compiler fixtures exercise fail-closed no-hxrt eligibility, emitted-runtime rejection, scoped borrow escape checks, overlap checks, typed native facades, and warning-clean Cargo builds.
  - `test:diagnostic-contract` (executable): The diagnostic registry and runtime fixture check keep borrow, no-hxrt, metadata, Cargo, dynamic, and reflection failures source-facing and versioned.
  - `test:snapshots-and-clippy` (executable): Characterized Rust output, Cargo builds, rustfmt expectations, deny-warnings coverage, and curated Clippy checks detect output-shape regressions.
  - `docs:lifetime-boundary` (documentary): The design documents define which lexical borrows are modeled in typed Haxe and when lifetimes, HRTB, const generics, macros, layout, or unsafe remain inside a typed Rust implementation island.
- Qualifications: none for this exact narrow claim.
- Does not mean:
  - The current Haxe diagnostics cover every provenance or lifetime relation rustc can express.
  - rustc diagnostics are already mapped perfectly back to originating Haxe expressions.
  - Arbitrary borrowed values can be stored or returned from Haxe without a typed boundary design.
- Owner Beads: `haxe.rust-oo3.98.1`
- Blocking Beads: none
- Remaining-gap Beads: `haxe.rust-oo3.98.5`

### ownership.scoped-borrow-safety

- Status: **Qualified**
- Question: Are the compiler's current borrow-shaped Haxe APIs sound and complete enough for useful work?
- Verdict: They are useful and fail closed for the admitted lexical region model, including direct and first-wave alias, wrapper, storage, throw, overlap, and spawn-capture cases. Provenance and diagnostic attribution remain incomplete beyond that model.
- Maps objections: `duplicate-borrow-checker`
- Mechanisms:
  - Borrow.withRef and Borrow.withMut create callback-scoped borrow-only tokens.
  - SliceTools, MutSliceTools, and StrTools expose borrowed Rust views without materializing owned clones where their contracts permit it.
  - The analyzer unwraps typed wrappers and local aliases for admitted escape and overlap checks.
- Concrete counterexamples to the impossibility argument:
  - Owned values derived from a borrow return normally, while returning, storing, throwing, or closure-capturing the token is rejected.
  - Sequential mutable borrows compile and overlapping same-local mutable regions fail before Rust emission.
- Evidence:
  - `test:metal-policy` (executable): Positive and negative compiler fixtures exercise fail-closed no-hxrt eligibility, emitted-runtime rejection, scoped borrow escape checks, overlap checks, typed native facades, and warning-clean Cargo builds.
  - `test:diagnostic-contract` (executable): The diagnostic registry and runtime fixture check keep borrow, no-hxrt, metadata, Cargo, dynamic, and reflection failures source-facing and versioned.
  - `test:snapshots-and-clippy` (executable): Characterized Rust output, Cargo builds, rustfmt expectations, deny-warnings coverage, and curated Clippy checks detect output-shape regressions.
  - `docs:lifetime-boundary` (documentary): The design documents define which lexical borrows are modeled in typed Haxe and when lifetimes, HRTB, const generics, macros, layout, or unsafe remain inside a typed Rust implementation island.
- Qualifications:
  - Unknown closure variables and helper-call side effects need richer provenance analysis.
  - Field and static source identity and source-equivalence checks are narrower than local-variable analysis.
  - Residual rustc diagnostics do not yet reliably map generated spans back to the originating Haxe expression.
- Does not mean:
  - The compiler implements Rust's undocumented or complete borrow-checker semantics.
  - Lifetime-heavy APIs should be forced through increasingly clever callback syntax.
  - A green Haxe analysis can bypass rustc's final validation.
- Owner Beads: `haxe.rust-oo3.98.5`
- Blocking Beads: none
- Remaining-gap Beads: `haxe.rust-oo3.98.5`

### interop.lifetime-islands

- Status: **Qualified**
- Question: Can Haxe use lifetime-heavy or RAII-heavy Rust APIs without adding lifetime annotations throughout normal Haxe code?
- Verdict: Yes through two bounded patterns: scoped callbacks for simple lexical guards and small typed extern/native implementation islands for lifetimes, HRTB, const generics, macros, layout, partial moves, or contained unsafe that Haxe cannot express cleanly.
- Maps objections: `runtime-interop-friction`, `duplicate-borrow-checker`, `lifetime-annotated-source-and-stdlib`
- Mechanisms:
  - Simple guards keep the real Rust guard alive for the callback and expose only a scoped typed token.
  - Complex Rust-only relationships stay in a narrow .rs module behind a typed Haxe extern or rust.* facade.
  - The native-facade manifest prevents helper islands from growing into a dynamic shadow runtime.
- Concrete counterexamples to the impossibility argument:
  - The metal_extern_lifetime_island fixture compiles a typed Haxe facade over a Rust module without lifetime syntax in application Haxe.
  - Mutex and RwLock callback APIs preserve the real guard lifetime and reject same-handle reentrancy rather than simulating a guard in Haxe.
- Evidence:
  - `test:snapshots-and-clippy` (executable): Characterized Rust output, Cargo builds, rustfmt expectations, deny-warnings coverage, and curated Clippy checks detect output-shape regressions.
  - `test:metal-policy` (executable): Positive and negative compiler fixtures exercise fail-closed no-hxrt eligibility, emitted-runtime rejection, scoped borrow escape checks, overlap checks, typed native facades, and warning-clean Cargo builds.
  - `contract:native-facades` (generated): Every shipped Rust helper island declares its Haxe owner, no-hxrt or hxrt-bridge contract, lowering rationale, dependencies, forbidden growth, evidence owner, and line budget.
  - `docs:lifetime-boundary` (documentary): The design documents define which lexical borrows are modeled in typed Haxe and when lifetimes, HRTB, const generics, macros, layout, or unsafe remain inside a typed Rust implementation island.
- Qualifications:
  - There is not yet a real-crate conformance matrix across borrowing returns, callbacks, RAII, traits, const generics, macros, and contained unsafe.
  - Every helper island still needs an explicit reason that compiler lowering is insufficient.
  - Haxe does not and should not pretend to expose arbitrary Rust lifetime parameter syntax one-to-one.
- Does not mean:
  - Every Rust crate API can be represented directly as an ordinary Haxe declaration.
  - Extern islands may use Dynamic, broad handles, untyped application APIs, or catch-all helper modules.
  - The boundary removes the need for Rust expertise when designing a lifetime-heavy wrapper.
- Owner Beads: `haxe.rust-oo3.98.6`
- Blocking Beads: none
- Remaining-gap Beads: `haxe.rust-oo3.98.6`

### interop.typed-rust-crates

- Status: **Qualified**
- Question: Can Rust developers use real crates and native resources without a universal dynamic or GC-shaped ABI?
- Verdict: Yes for existing typed externs, metadata-driven Cargo dependencies, owned native facades, fail-closed no-hxrt fixtures, and documented implementation islands. Breadth across advanced trait and lifetime patterns is not yet sufficient for an unqualified interop claim.
- Maps objections: `runtime-interop-friction`, `lifetime-annotated-source-and-stdlib`
- Mechanisms:
  - Typed Haxe externs and metadata add Cargo dependencies and preserve native module ownership.
  - Rust-native facades own files, commands, child processes, sockets, paths, errors, and RAII resources through typed public Haxe surfaces.
  - No-hxrt fixtures prove selected crate/native paths do not pass through HxRef or Dynamic.
- Concrete counterexamples to the impossibility argument:
  - Owned file, command, TCP, and UDP operations compile and run behind typed rust.* facades with no bundled hxrt.
  - Fresh dependency resolution and Cargo builds exercise actual Rust dependency graphs rather than mocked extern declarations.
- Evidence:
  - `test:metal-policy` (executable): Positive and negative compiler fixtures exercise fail-closed no-hxrt eligibility, emitted-runtime rejection, scoped borrow escape checks, overlap checks, typed native facades, and warning-clean Cargo builds.
  - `contract:native-facades` (generated): Every shipped Rust helper island declares its Haxe owner, no-hxrt or hxrt-bridge contract, lowering rationale, dependencies, forbidden growth, evidence owner, and line budget.
  - `test:fresh-cargo-resolution` (executable): Representative portable and metal dependency graphs resolve twice from an empty Cargo cache on the supported minimum Rust and match immutable baselines.
  - `test:snapshots-and-clippy` (executable): Characterized Rust output, Cargo builds, rustfmt expectations, deny-warnings coverage, and curated Clippy checks detect output-shape regressions.
- Qualifications:
  - The @:rustCargo grammar still needs a structured stable contract before broad third-party dependency admission.
  - Where clauses, associated types, object safety, orphan diagnostics, HRTB, const generics, macro-heavy setup, and contained unsafe need a representative real-crate matrix.
  - Some helpers remain classified as lowering candidates or hxrt bridges and must not be presented as zero-cost native values.
- Does not mean:
  - Every crate on crates.io has a ready-made Haxe binding.
  - All extern calls are zero-copy or no-allocation.
  - Raw Rust snippets in application code are a supported substitute for typed interop.
- Owner Beads: `haxe_rust-p6hs.10`, `haxe.rust-oo3.98.6`
- Blocking Beads: none
- Remaining-gap Beads: `haxe_rust-p6hs.10`, `haxe.rust-oo3.98.2`, `haxe.rust-oo3.98.6`

### stdlib.portable-contract

- Status: **Qualified**
- Question: Does Haxe need a lifetime-annotated Rust-shaped replacement stdlib before ordinary programs can compile?
- Verdict: No lifetime-annotated source stdlib is required for the admitted portable surface. The backend uses Haxe std overrides, typed lowering, thin runtime primitives where semantics require them, and separate rust.* facades for native ownership; proof depth is still tiered by operation.
- Maps objections: `lifetime-annotated-source-and-stdlib`
- Mechanisms:
  - Portable Haxe APIs remain Haxe-shaped while compiler lowering selects direct Rust or narrow hxrt behavior.
  - The public compatibility graph inventories the installed Haxelib surface and the semantic-confidence report keeps compile coverage separate from runtime parity.
  - Rust-native ownership surfaces live under rust.* rather than weakening portable sys.* semantics.
- Concrete counterexamples to the impossibility argument:
  - Tiered upstream stdlib sweeps compile ordinary Haxe modules without adding Rust lifetime syntax to those modules.
  - Semantic-differential and failure/lifecycle fixtures prove selected std operations against Haxe behavior while the remaining smoke-only buckets stay labeled.
- Evidence:
  - `test:semantic-differential` (executable): Haxe and generated Rust are compared on curated semantic oracles; the generated confidence report separately classifies semantic, compile-inventory, and smoke-only proof.
  - `contract:public-compatibility` (generated): The generated installed-Haxelib type and operation graph classifies stable-candidate, qualified, experimental, and excluded public surfaces without pretending structural inventory is semantic proof.
  - `test:full-harness` (executable): The repository harness composes snapshots, semantic oracles, lifecycle, toolchain, report, diagnostics, metal policy, package/template, examples, and native parity gates.
- Qualifications:
  - Structural compile inventory is not blanket semantic parity.
  - High-risk reference, exception, reflection, IO, process, network, DB, TLS, concurrency, platform, and failure paths require the strongest applicable evidence class before stable promotion.
  - Environment-sensitive and platform-sensitive operations remain explicitly qualified.
- Does not mean:
  - Every upstream Haxe std module or operation is stable and semantically proven.
  - Portable sys.* APIs should be rewritten as direct Rust handles when Haxe compatibility needs runtime state.
  - A green Tier2 sweep proves failure, lifecycle, or host behavior.
- Owner Beads: `haxe.rust-oo3.98.7`
- Blocking Beads: none
- Remaining-gap Beads: `haxe.rust-oo3.98.7`

### output.handwritten-rust-quality

- Status: **Qualified**
- Question: Does typeful Haxe already emit readable, idiomatic, warning-clean Rust with hand-written-Rust-like cost?
- Verdict: Readable, rustfmt-friendly, warning-clean output is an enforced product requirement and is proved on curated fixtures. Equivalent cost and idiom are demonstrated on bounded paths, especially metal/no-hxrt, but not yet across class-heavy and sustained mixed workloads.
- Maps objections: `runtime-interop-friction`, `lifetime-annotated-source-and-stdlib`
- Mechanisms:
  - AST-first lowering, snapshots, rustfmt, deny-warnings, curated Clippy, metal idiom counters, and runtime-plan reports make emitted shape reviewable.
  - Compiler-only lowering is preferred when typed AST information gives a closed answer.
  - Native helpers and hxrt additions have manifests and austerity rules so convenience wrappers cannot silently define output quality.
- Concrete counterexamples to the impossibility argument:
  - Metal no-hxrt hot-loop output and typed owned facades compile as ordinary Rust without a semantic runtime.
  - Snapshot and warning gates catch clone, borrow, diverging-expression, iterator, nullable, and raw-emission regressions in generated Rust.
- Evidence:
  - `test:snapshots-and-clippy` (executable): Characterized Rust output, Cargo builds, rustfmt expectations, deny-warnings coverage, and curated Clippy checks detect output-shape regressions.
  - `test:metal-policy` (executable): Positive and negative compiler fixtures exercise fail-closed no-hxrt eligibility, emitted-runtime rejection, scoped borrow escape checks, overlap checks, typed native facades, and warning-clean Cargo builds.
  - `test:hxrt-performance` (executable): The benchmark protocol tracks size, startup, throughput, and selected output-shape counters, including a metal no-hxrt lower-bound signal.
  - `contract:native-facades` (generated): Every shipped Rust helper island declares its Haxe owner, no-hxrt or hxrt-bridge contract, lowering rationale, dependencies, forbidden growth, evidence owner, and line budget.
- Qualifications:
  - RustCompiler and parts of RustAST still hide analysis-relevant syntax in raw strings, limiting structural optimization and source mapping.
  - Portable class/reference workloads have not yet established allocation, clone, lock, dispatch, binary-size, and lifecycle budgets against hand-written Rust models.
  - The current performance suite is microcase-oriented and does not yet prove tail latency, sustained RSS trend, or mixed-workload operability.
- Does not mean:
  - All generated Rust is indistinguishable from expert hand-written Rust.
  - A warning-clean build proves optimal allocation, ownership, or dispatch behavior.
  - Users should contort Haxe source around current lowering artifacts.
- Owner Beads: `haxe.rust-oo3.98.2`, `haxe.rust-oo3.98.3`, `haxe.rust-oo3.98.4`, `haxe.rust-oo3.98.8`
- Blocking Beads: none
- Remaining-gap Beads: `haxe.rust-oo3.98.2`, `haxe.rust-oo3.98.3`, `haxe.rust-oo3.98.4`, `haxe.rust-oo3.98.8`

### maturity.bounded-production

- Status: **Qualified**
- Question: Is the compiler usable by Haxe and Rust developers for real production work today?
- Verdict: Yes for controlled production on validated lanes with app-specific tests around the runtime, native, platform, and failure paths the application actually uses. The independent audit does not authorize stable 1.0 or universal Haxe/std/sys parity.
- Maps objections: `gc-required`, `runtime-interop-friction`, `duplicate-borrow-checker`, `lifetime-annotated-source-and-stdlib`
- Mechanisms:
  - The full harness composes compiler, runtime, semantic, lifecycle, toolchain, report, diagnostics, packaging, example, native, and release evidence.
  - The independent codex-hxrust application pressure-tests the normal portable and metal workflows without compiler-specific scenarios.
  - Public compatibility and production-readiness documents distinguish stable candidates, qualifications, experiments, exclusions, and release blockers.
- Concrete counterexamples to the impossibility argument:
  - The compiler builds and tests a separate application through its normal documented commands rather than only compiling toy fixtures.
  - The independent audit found a credible bounded-production posture while explicitly rejecting stable 1.0 at the reviewed evidence point.
- Evidence:
  - `test:full-harness` (executable): The repository harness composes snapshots, semantic oracles, lifecycle, toolchain, report, diagnostics, metal policy, package/template, examples, and native parity gates.
  - `test:independent-consumer` (independent): The sibling application runs its normal portable and metal commands as app-level pressure without becoming a compiler-owned fixture or receiving compiler-specific behavior.
  - `contract:public-compatibility` (generated): The generated installed-Haxelib type and operation graph classifies stable-candidate, qualified, experimental, and excluded public surfaces without pretending structural inventory is semantic proof.
  - `audit:bounded-production` (independent): The reviewed disposition separates bounded production readiness from stable 1.0 and records verified architecture, evidence, provenance, and release gaps.
- Qualifications:
  - Applications must validate the exact networking, TLS, DB, process, threading, platform, dynamic, exception, and native-crate paths they use.
  - Broad workload performance, advanced interop breadth, complete source-mapped diagnostics, and operation-level std semantic admission remain open capability tracks.
  - Stable-major release authorization has separate provenance, dependency-resolution, and final-review gates.
- Does not mean:
  - Every arbitrary Haxe program is production-ready on every host.
  - A green local harness alone proves a specific application or dependency graph.
  - Bounded production readiness is stable 1.0 authorization.
- Owner Beads: `haxe.rust-oo3.98.7`, `haxe.rust-oo3.98.8`, `haxe.rust-oo3.98.10`
- Blocking Beads: none
- Remaining-gap Beads: `haxe.rust-oo3.98.7`, `haxe.rust-oo3.98.8`, `haxe.rust-oo3.98.10`

### maturity.unqualified-objection-closure

- Status: **Open**
- Question: Can the project publicly claim that it has completely solved Haxe-to-Rust and all four historical objections?
- Verdict: Not yet. The architecture defeats the claimed impossibility and several narrow mechanisms are closed, but the remaining qualified claims need their dependency-ordered evidence and an independent claim-by-claim authorization.
- Maps objections: `gc-required`, `runtime-interop-friction`, `duplicate-borrow-checker`, `lifetime-annotated-source-and-stdlib`
- Mechanisms:
  - This manifest separates exact closed mechanisms from qualified product claims and one open broad claim.
  - The capability epic orders typed IR, representation, memory, borrow, interop, std, workload, cycle, and independent-review work.
  - The final decision requires an inventory-verified evidence bundle rather than confidence inferred from implementation volume.
- Concrete counterexamples to the impossibility argument:
  - No-hxrt, scoped borrows, typed extern islands, portable std sweeps, and independent consumer builds already contradict the claim that the compiler is impossible.
  - Open class-heavy, advanced interop, source-mapping, operation-semantic, workload, and cycle decisions prevent those counterexamples from becoming a universal claim.
- Evidence:
  - `test:full-harness` (executable): The repository harness composes snapshots, semantic oracles, lifecycle, toolchain, report, diagnostics, metal policy, package/template, examples, and native parity gates.
  - `test:independent-consumer` (independent): The sibling application runs its normal portable and metal commands as app-level pressure without becoming a compiler-owned fixture or receiving compiler-specific behavior.
  - `audit:bounded-production` (independent): The reviewed disposition separates bounded production readiness from stable 1.0 and records verified architecture, evidence, provenance, and release gaps.
- Qualifications:
  - The allowed statement is the bounded wording in publicAnswer.allowed, not a universal solved claim.
- Does not mean:
  - The current compiler is a failed proof of concept.
  - Every remaining item is a prerequisite for all production use.
  - Completing this capability review automatically authorizes stable 1.0.
- Owner Beads: `haxe.rust-oo3.98.10`
- Blocking Beads: `haxe.rust-oo3.98.10`
- Remaining-gap Beads: `haxe.rust-oo3.98.2`, `haxe.rust-oo3.98.3`, `haxe.rust-oo3.98.4`, `haxe.rust-oo3.98.5`, `haxe.rust-oo3.98.6`, `haxe.rust-oo3.98.7`, `haxe.rust-oo3.98.8`, `haxe.rust-oo3.98.9`, `haxe.rust-oo3.98.10`

## Evidence Registry

The registry names evidence authorities; it intentionally does not copy their changing counts or detailed inventories.

### test:hxref-lifecycle

- Class: `executable`
- Purpose: Rust Drop counters and weak observers prove alias-visible identity and deterministic cleanup for admitted acyclic HxRef payloads while preserving the explicit strong-cycle boundary.
- Paths: [`runtime/hxrt/src/hxref.rs`](../runtime/hxrt/src/hxref.rs), [`docs/hxref-lifecycle.md`](hxref-lifecycle.md)
- Commands: `npm run test:hxref-lifecycle`

### test:metal-policy

- Class: `executable`
- Purpose: Positive and negative compiler fixtures exercise fail-closed no-hxrt eligibility, emitted-runtime rejection, scoped borrow escape checks, overlap checks, typed native facades, and warning-clean Cargo builds.
- Paths: [`scripts/ci/check-metal-policy.sh`](../scripts/ci/check-metal-policy.sh), [`test/positive/metal_no_hxrt_minimal`](../test/positive/metal_no_hxrt_minimal), [`test/negative/metal_no_hxrt_runtime_boundary`](../test/negative/metal_no_hxrt_runtime_boundary), [`test/positive/borrow_mut_disjoint_scopes`](../test/positive/borrow_mut_disjoint_scopes), [`test/negative/metal_ref_alias_return_escape`](../test/negative/metal_ref_alias_return_escape)
- Commands: `bash scripts/ci/check-metal-policy.sh`

### test:diagnostic-contract

- Class: `executable`
- Purpose: The diagnostic registry and runtime fixture check keep borrow, no-hxrt, metadata, Cargo, dynamic, and reflection failures source-facing and versioned.
- Paths: [`docs/diagnostic-contract.json`](diagnostic-contract.json), [`scripts/ci/diagnostic-contract-check.js`](../scripts/ci/diagnostic-contract-check.js), [`scripts/ci/check-diagnostic-contract.sh`](../scripts/ci/check-diagnostic-contract.sh)
- Commands: `npm run test:diagnostic-contract`, `npm run test:diagnostic-contract:runtime`

### test:snapshots-and-clippy

- Class: `executable`
- Purpose: Characterized Rust output, Cargo builds, rustfmt expectations, deny-warnings coverage, and curated Clippy checks detect output-shape regressions.
- Paths: [`test/run-snapshots.sh`](../test/run-snapshots.sh), [`test/snapshot/deny_warnings`](../test/snapshot/deny_warnings), [`test/snapshot/metal_extern_lifetime_island`](../test/snapshot/metal_extern_lifetime_island), [`test/snapshot/metal_trait_impl_bounds`](../test/snapshot/metal_trait_impl_bounds)
- Commands: `npm test`, `bash test/run-snapshots.sh --clippy`

### test:semantic-differential

- Class: `executable`
- Purpose: Haxe and generated Rust are compared on curated semantic oracles; the generated confidence report separately classifies semantic, compile-inventory, and smoke-only proof.
- Paths: [`test/run-semantic-diff.py`](../test/run-semantic-diff.py), [`test/semantic_diff`](../test/semantic_diff), [`docs/semantic-confidence-summary.json`](semantic-confidence-summary.json), [`docs/semantic-confidence-summary.md`](semantic-confidence-summary.md)
- Commands: `npm run test:semantic-diff`, `npm run docs:check:evidence`

### contract:public-compatibility

- Class: `generated`
- Purpose: The generated installed-Haxelib type and operation graph classifies stable-candidate, qualified, experimental, and excluded public surfaces without pretending structural inventory is semantic proof.
- Paths: [`docs/public-compatibility-manifest.json`](public-compatibility-manifest.json), [`docs/pre-1.0-compatibility-review.md`](pre-1.0-compatibility-review.md), [`scripts/ci/public-compatibility-manifest-check.js`](../scripts/ci/public-compatibility-manifest-check.js)
- Commands: `npm run guard:public-compatibility`, `npm run test:public-compatibility`

### contract:native-facades

- Class: `generated`
- Purpose: Every shipped Rust helper island declares its Haxe owner, no-hxrt or hxrt-bridge contract, lowering rationale, dependencies, forbidden growth, evidence owner, and line budget.
- Paths: [`docs/native-facade-manifest.json`](native-facade-manifest.json), [`docs/native-facade-policy.md`](native-facade-policy.md), [`scripts/ci/native-facade-manifest-check.js`](../scripts/ci/native-facade-manifest-check.js)
- Commands: `npm run guard:native-facade-manifest`

### test:hxrt-performance

- Class: `executable`
- Purpose: The benchmark protocol tracks size, startup, throughput, and selected output-shape counters, including a metal no-hxrt lower-bound signal.
- Paths: [`scripts/ci/perf-hxrt-overhead.sh`](../scripts/ci/perf-hxrt-overhead.sh), [`docs/perf-hxrt-overhead.md`](perf-hxrt-overhead.md), [`test/perf/hot_loop_no_hxrt`](../test/perf/hot_loop_no_hxrt)
- Commands: `npm run test:perf:hxrt`

### test:full-harness

- Class: `executable`
- Purpose: The repository harness composes snapshots, semantic oracles, lifecycle, toolchain, report, diagnostics, metal policy, package/template, examples, and native parity gates.
- Paths: [`scripts/ci/harness.sh`](../scripts/ci/harness.sh)
- Commands: `npm run test:all`

### test:independent-consumer

- Class: `independent`
- Purpose: The sibling application runs its normal portable and metal commands as app-level pressure without becoming a compiler-owned fixture or receiving compiler-specific behavior.
- Paths: [`scripts/ci/check-codex-hxrust-smoke.sh`](../scripts/ci/check-codex-hxrust-smoke.sh)
- Commands: `npm run test:codex-hxrust`

### test:fresh-cargo-resolution

- Class: `executable`
- Purpose: Representative portable and metal dependency graphs resolve twice from an empty Cargo cache on the supported minimum Rust and match immutable baselines.
- Paths: [`scripts/ci/fresh-cargo-resolution.js`](../scripts/ci/fresh-cargo-resolution.js), [`test/compatibility-baselines/fresh-cargo-resolution`](../test/compatibility-baselines/fresh-cargo-resolution), [`docs/rust-toolchain-policy.md`](rust-toolchain-policy.md)
- Commands: `npm run test:fresh-cargo-resolution`

### docs:lifetime-boundary

- Class: `documentary`
- Purpose: The design documents define which lexical borrows are modeled in typed Haxe and when lifetimes, HRTB, const generics, macros, layout, or unsafe remain inside a typed Rust implementation island.
- Paths: [`docs/lifetime-encoding.md`](lifetime-encoding.md), [`docs/extern-lifetime-island-cookbook.md`](extern-lifetime-island-cookbook.md), [`docs/raii-guard-lifetime-islands.md`](raii-guard-lifetime-islands.md)
- Commands: none (documentary authority)

### audit:bounded-production

- Class: `independent`
- Purpose: The reviewed disposition separates bounded production readiness from stable 1.0 and records verified architecture, evidence, provenance, and release gaps.
- Paths: [`docs/production-readiness-audit-2026-07-13.md`](production-readiness-audit-2026-07-13.md), [`docs/oracle-gpt-5.6-production-readiness-review.md`](oracle-gpt-5.6-production-readiness-review.md)
- Commands: none (documentary authority)

## Status Change Rules

- `closed`: the exact claim cites executable evidence and has no qualification or blocker hidden in its wording.
- `qualified`: exact exclusions, an owner, and remaining-gap Beads are mandatory.
- `open`: at least one blocking Bead is mandatory.
- Final broad authorization remains owned by `haxe.rust-oo3.98.10`, not by a green generator run.
