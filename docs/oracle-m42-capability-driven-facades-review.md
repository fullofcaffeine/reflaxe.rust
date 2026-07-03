# Oracle Review: M42 Capability-Driven Portable Facades

This is the paste-ready external Oracle/GPT-5.5 Pro review prompt for
`haxe.rust-oo3.74.9`.

## Review Result

Oracle verdict: `APPROVE_WITH_CHANGES`.

Accepted direction:

- capability-driven portable facades are coherent,
- profiles should remain policy presets,
- typed surfaces/imports/metadata/reports should own semantics,
- the model must not introduce a hidden third profile or silent semantic inference.

Required changes before closure:

- Keep `haxe.rust-oo3.74.9` open until concrete compiler/report fixtures land.
- Reconcile current `rust_no_hxrt` metal-only implementation with any future portable no-runtime
  claim. Today it remains metal-only; future portable support requires source/typed-AST eligibility
  before the final generated-code `NoHxrtPass`.
- Define per-surface facade admission, not namespace-wide `reflaxe.std.*` admission.
- Add reportable surface contracts, native representation decisions, and semantic runtime fallback
  reasons.
- Split current `Option` / `Result` facade proof from any future `Vec`/collection facade proof.

## Uploads

Upload this current repo bundle:

- `repomix-output.haxe-rust-m42-capability-20260703.xml.zip`

Notes:

- The bundle was generated after commit `eafa5eb7` with Repomix.
- Repomix excluded two SSL SNI fixture files during its security scan. They are unrelated to this
  review.
- Do not use the older `repomix-output.haxe-rust.xml.zip` for this review; it predates the latest
  capability-driven facade docs.
- `runtime.zip` is not needed unless the reviewer specifically asks for a smaller runtime-only
  bundle.

## Files To Inspect

Ask Oracle to prioritize these files in the uploaded bundle:

- `AGENTS.md`
- `docs/profiles.md`
- `docs/metal-haxified-rust-roadmap.md`
- `docs/portable-near-native-guidance.md`
- `docs/portable-vs-metal-authoring.md`
- `docs/metal-type-surface-gap-matrix.md`
- `docs/metal-capability-fixtures.md`
- `docs/lifetime-encoding.md`
- `docs/reflaxe-std-adoption-contract.md`
- `docs/metal-profile.md`
- `.beads/issues.jsonl` entries for `haxe.rust-oo3.74` and `haxe.rust-oo3.74.9`
- `src/reflaxe/rust/ProfileResolver.hx`
- `src/reflaxe/rust/CompilerInit.hx`
- `src/reflaxe/rust/analyze/ProfileContractAnalyzer.hx`
- `src/reflaxe/rust/analyze/HxrtFeatureAnalyzer.hx`
- `src/reflaxe/rust/passes/NoHxrtPass.hx`
- `src/reflaxe/rust/emit/ProjectEmitter.hx`
- `src/reflaxe/rust/RustCompiler.hx`
- `std/rust/Option.hx`
- `std/rust/Result.hx`
- `std/rust/Vec.hx`
- `std/rust/Ref.hx`
- `std/rust/MutRef.hx`
- `std/rust/Slice.hx`
- `std/rust/MutSlice.hx`
- `std/rust/Borrow.hx`
- `std/rust/HxRef.hx`
- `std/rust/adapters/ReflaxeStdAdapters.hx`
- `std/haxe/functional/Result.hx`
- `runtime/hxrt/src/dynamic.rs`

## Original Prompt

The prompt below is the original review request. The review result above supersedes any fixture names
or wording that Oracle asked us to change.

You are reviewing the Haxe-to-Rust target `reflaxe.rust`.

This is a second-pass architecture review for Bead `haxe.rust-oo3.74.9`,
part of Milestone 42: "Metal as haxified Rust".

The repo goal is to make Haxe-authored Rust production-grade:

- generated Rust should be readable, idiomatic, rustfmt-friendly, warning-clean, and close to
  hand-written Rust where Haxe semantics permit;
- `portable` remains the default Haxe-semantics contract;
- `metal` is the explicit Rust-first authoring contract;
- `hxrt` should be lightweight and used only where semantics require runtime support;
- `Dynamic`, reflection, raw target injection, broad runtime helpers, and clone-heavy output should
  be treated as compiler/API gaps unless they are required by source semantics.

Recent plan change to review:

The docs now frame the future portable/native convergence as **capability-driven portable facades**,
not as a hidden "portable-on-metal" third mode.

The intended model:

- profiles are policy presets, not the only source of native Rust output;
- typed APIs/imports/metadata declare semantics;
- ordinary Haxe/std APIs preserve Haxe semantics first;
- `reflaxe.std.*`-style APIs can be portable facades that declare native Rust representations for
  this backend;
- `rust.*` and `rust.metal.*` are explicit Rust-native source contracts;
- `@:haxeMetal` marks strict Rust-native islands inside a wider portable build;
- `rust_no_hxrt` proves that the selected subset does not need the Haxe runtime;
- the compiler should specialize at compile time first;
- `hxrt` is a reported semantic fallback only when required by source semantics such as object
  identity, Haxe reference mutation, `Dynamic`, reflection, anonymous runtime objects, exceptions,
  nullable compatibility, shared closure cells, or a real platform abstraction.

Please review whether this architecture is coherent and safe.

Focus questions:

1. Does the capability-driven model preserve the `portable`/`metal` contract boundary, or does it
   risk reintroducing hidden semantic mode inference?
2. Are "profiles are policy presets; typed surfaces declare semantics" and "native Rust lowering
   when the facade contract permits it" precise enough to guide compiler implementation?
3. Are the proposed facade admission rules sufficient?
   Required rules in current docs include cross-target source contract, explicit Rust
   specialization, no hidden `rust.*` import requirement, no silent switch from ordinary portable
   semantics to Rust-native semantics, no-hxrt eligibility, and deterministic fallback reasons.
4. Does the plan correctly keep `hxrt` as semantic fallback rather than normalizing runtime-heavy
   lowering?
5. Are the planned fixture entries enough for a first implementation wave?
   Specifically review:
   - `test/snapshot/portable_facade_native_option_result_vec`
   - `test/positive/portable_facade_no_hxrt_subset`
   - `test/negative/portable_facade_no_hxrt_dynamic_fallback`
   - deterministic fallback-reason report fixture
6. What compiler artifacts or report schemas should exist before implementing this layer?
   Consider `contract_report.*`, `runtime_plan.*`, `NoHxrtPass`, `HxrtFeatureAnalyzer`, and
   output-shape gates.
7. Does the plan avoid overpromising full Rust parity in Haxe?
   Pay special attention to lifetimes, HRTB, trait bounds, const generics, unsafe APIs, and
   macro-heavy Rust libraries.
8. What are the top architecture risks or missing Beads tasks before implementation should begin?
9. Are any current docs misleading, contradictory, or too vague?
10. Should `haxe.rust-oo3.74.9` be closed after this docs/plan update, or should it remain open
    until a concrete compiler/report fixture is added?

Please return:

- verdict: `APPROVE`, `APPROVE_WITH_CHANGES`, or `BLOCK`;
- top findings ordered by severity;
- concrete doc edits or Beads task changes to make;
- any recommended compiler/report fixture contract additions;
- a short final note suitable to paste into the `haxe.rust-oo3.74.9` Beads comment.
