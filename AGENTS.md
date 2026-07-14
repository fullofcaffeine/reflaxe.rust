# AI/Agent Instructions for `reflaxe.rust`

## Issue Tracking

This project uses **bd (beads)** for issue tracking.

- `bd prime` — workflow context
- `bd ready` — unblocked work
- `bd show <id>` — details
- `bd update <id> --claim` — claim
- `bd close <id>` — complete
- `bd export -o .beads/issues.jsonl` — write the git-tracked issue export from the embedded DB
- `bd dolt push` / `bd dolt pull` — sync the embedded Dolt DB once a remote is configured

Gotcha: `bd` DB state and `.beads/issues.jsonl` can drift because the JSONL file is an explicit export of the embedded Dolt database.
Before committing bead status changes, run `bd export -o .beads/issues.jsonl` and ensure `.beads/issues.jsonl` is included in the commit when modified.
- `.beads/interactions.jsonl` is also tracked as the Beads interaction/audit log. `bd export` does not rewrite it,
  but `bd update` / `bd close` can append to it; if it is modified by the Beads work being committed,
  include it with the Beads bookkeeping unless you are intentionally leaving local interaction history out.
- Modern Beads migration gotcha: this repo has been migrated to the embedded Dolt backend (`bd context` should report `Backend: dolt`, `mode: embedded`).
  Do not use legacy direct SQLite-style `bd --db .beads/beads.db ...` commands; they can open an empty legacy database and remove/hide the JSONL export.
  If recovery is needed, first copy `.beads/issues.jsonl` to a temp path, then run `bd init --from-jsonl --reinit-local --prefix haxe.rust --skip-agents --skip-hooks --non-interactive`
  and verify `bd status` matches the JSONL counts before mutating issues.
  The modern backend normalizes the configured prefix to `haxe_rust`; when adding children to the historical `haxe.rust-*` roadmap, use explicit IDs with `bd create --force --id ...`.
  Do not combine `bd create --force --id ...` with `--parent`; the modern CLI rejects that pair.
  For explicit historical IDs such as `haxe.rust-oo3.76`, create the issue with the explicit ID,
  let Beads infer the dotted hierarchy, then add only the sibling blocker dependencies you need and
  run `bd export -o .beads/issues.jsonl`.
  Dependency direction gotcha: `bd create --deps blocks:OTHER` means the new issue blocks `OTHER`,
  so the new issue must close before `OTHER`. To model "this issue waits for OTHER", use the
  appropriate depends-on edge instead of `blocks:OTHER`.

Milestone plan lives in Beads under epic `haxe.rust-oo3` (see `bd graph haxe.rust-oo3 --compact`).

## Thinking Levels (Bead Labels)

Use a `thinking:*` label on active beads so execution effort matches task risk.

- `thinking:low`
  - Mechanical edits, simple docs cleanup, straightforward renames, obvious wiring.
- `thinking:medium`
  - CI/job plumbing, runner scripts, artifact flow, bounded retry/timeout logic.
- `thinking:high`
  - Parity contracts, gate semantics, dependency graph changes, perf-policy changes, compiler/runtime architecture decisions.
- `thinking:xhigh`
  - Scope-definition changes, release enforcement, provenance-sensitive implementation strategy, or any task where a wrong decision would create misleading 1.0 evidence.

Agent policy:

- When a bead has a `thinking:*` label, match reasoning depth to that label automatically.
- If a claimed bead has no `thinking:*` label, infer one immediately and add it before substantial work.
- `thinking:xhigh` should get a second-pass review before closure.
  - Preferred: an Oracle checkpoint/review.
    - Default Oracle workflow: prepare a detailed prompt for GPT-5.5 Pro in the web UI, including the review questions, relevant file paths, Beads IDs/commands, and any repo bundles to upload (for example a repomix archive). Give that prompt to the user to paste, wait for the user to paste the reply back, then incorporate the findings.
    - Oracle bundle completeness gotcha: do not assume a Repomix/archive command included tracked,
      vendored, hidden, lock, license, generated-consumer, or release-artifact files merely because
      they were requested in the prompt. Before handoff, inspect the archive inventory and record
      the reviewed commit plus artifact names/sizes/digests. Treat a reviewer report that a requested
      file was absent as an evidence-bundle omission until the repository and hosted artifact are
      checked independently; do not create a fake product defect from an upload omission.
    - Do not use a subagent for Oracle-style review unless the user explicitly asks for one.
  - Acceptable fallback: an explicit written second-pass design review recorded in the bead comments.
- Oracle is a review/escalation tool for `thinking:xhigh`; it is not a substitute for implementation, tests, or CI evidence.

## Product Source of Truth

- Requirements + architecture: `prd.md`
- Target: **Haxe 4.3.7 → Rust** via Reflaxe

## Strategic Goal

- Primary long-term goal: make `reflaxe.rust` the best way to write production Rust outside of writing raw Rust directly, by combining Haxe ergonomics with Rust-level performance, safety, and readability, while preserving an explicit portable path through Haxe when users want cross-target portability.
- Use Bun-class systems software as a production-quality north star: the compiler should be capable
  in principle of supporting serious performance-sensitive, cross-platform systems applications of
  comparable complexity without routine handwritten-Rust escape hatches or app-specific compiler
  behavior. This is a capability criterion, not a commitment to build or rewrite Bun. A future
  `BunHx` may be used as a bounded validation project, but any gap it exposes must be fixed as a
  generic compiler/runtime/typed-facade contract with reusable evidence.

## Typeful Haxe and Rust Output Quality

- Treat well-typed Haxe as the source language contract. Compiler, runtime, std overrides, tests, and examples should use concrete types, `typedef` schemas, abstracts/newtypes, enum abstracts, typed enums, and GADT-style typed enum patterns where Haxe can express them. Avoid strings as domain models when a stronger representation is practical.
- Keep stringly typed values at real boundaries only: JSON/protocol IO, CLI/env/filesystem inputs, metadata names, target syntax tokens, or upstream API compatibility points. Convert those values into typed structures immediately after the boundary and keep downstream code typed.
- Use macros when they improve correctness or maintainability: deriving repetitive validators/bridges, centralizing typed target metadata, enforcing profile/runtime contracts, or preventing schema drift. Avoid clever macro machinery whose generated shape is hard to inspect, hard to test, or harder for haxe.rust to lower cleanly.
- Adapt Rust/Codex-style architecture into Haxe idioms rather than mechanically mirroring Rust. Prefer Haxe abstractions that make invalid states unrepresentable while still giving the backend enough typed information to emit native Rust.
- For any Haxe-to-target compiler or framework layer, target compatibility is the floor, not the Haxe API design ceiling. Target-shaped Haxe APIs are fine when they are intentional and documented for migration, native interop, predictable lowering, performance, ownership, borrowing, or escape-hatch use. Keep 1:1 Rust-shaped facades available where they help users reason about the emitted target, but default canonical APIs to Haxe's strengths: strong types, abstracts, macros, generated references, properties, completion, and compile-time diagnostics. Prefer semantic Haxe wrappers when they improve readability or safety without changing Rust behavior or hiding target costs.
- Generated Rust quality is a first-class product requirement in every profile. Output should be readable, idiomatic, warning-clean, rustfmt-friendly, and close to hand-written Rust performance and runtime footprint wherever Haxe semantics permit. `hxrt` should remain lightweight and used only where semantics require runtime support.
- Stdlib lowering should prefer direct, idiomatic, efficient Rust or the thinnest typed runtime primitive that preserves the Haxe std contract. Do not route std APIs through broad runtime layers, dynamic handles, or allocation-heavy adapters just because it is easier to bind; use `hxrt` only when it is required for semantics, ownership/non-clone handles, platform abstraction, or shared safety checks. When `hxrt` is required, keep the helper narrow, typed, low-overhead, and shaped like hand-written Rust. If a stdlib API currently needs a heavier runtime path, track or fix that as a generic compiler/runtime improvement rather than normalizing the overhead.
- Runtime-helper austerity rule (strict): adding or expanding `hxrt` is a last resort, not a convenience path. Before touching `runtime/hxrt/**` or `std/hxrt/**`, add or review a fixture that states the desired emitted-Rust contract and attempt compiler-only lowering whenever the needed information is available from the typed AST, metadata, literals, or existing target primitives. Do **not** add runtime helpers for facts the compiler already knows or can cheaply encode, including optional/required field status, literal defaults, typed structural field reads, static access paths, nullable wrapping at typed callsites, borrow-region syntax, name/path normalization, or generic dispatch shape. An `hxrt` change is allowed only for semantics that genuinely exist at runtime, such as identity/aliasing storage, `Dynamic`/reflection payloads, exceptions/unwind payloads, platform/sys abstractions, cross-thread safety, shared ownership/interior mutability, or non-clone/native handles. If an `hxrt` helper is still required, document why generated code is insufficient in code comments plus Beads evidence, inspect the emitted Rust shape, and add focused coverage for both the runtime helper and generated callsite.
- Native facade helper policy (strict): `std/rust/native/*.rs` modules are typed Rust helper islands shipped with generated crates and must not become a shadow runtime. Prefer compiler lowering when the operation is a pure, closed transformation from typed AST, metadata, literals, or existing Rust primitives. A native helper is allowed only for a narrow typed `rust.*` / metal facade or documented std bridge that owns or safely wraps a real Rust type/resource the current Haxe/compiler surface cannot express cleanly without raw snippets, dynamic handles, layout assumptions, or noisy generated Rust. Valid reasons include private-field/native-layout wrappers, RAII/resource lifecycle, partial moves, pipe/stream/socket ownership, lifetimes/HRTB, const generics, trait impl bodies, macro-heavy setup, contained `unsafe`, narrow typed validation at a native boundary, or an explicit `hxrt-bridge` contract for existing Haxe runtime representations. Forbidden helper growth includes undeclared `hxrt` dependencies, `Dynamic`/`Any`, type-erased registries, broad handles, reflection-like dispatch, portable `sys.*` semantics under `rust.*`, generic platform abstraction, allocation-heavy adapters where direct Rust values are available, or catch-all helper modules that collect unrelated behavior. Every new or expanded helper must update `docs/native-facade-manifest.json` with its owning Haxe facade, why compiler lowering is insufficient today, classification (`permanent-native-facade`, `lowering-candidate`, or `experimental-scaffold`), runtime contract (`no-hxrt` or `hxrt-bridge`), allowed dependencies/imports, forbidden growth, evidence owner, and code-line review budget; then run `npm run guard:native-facade-manifest`.
- Generated Rust quality must be actively inspected for new compiler/runtime boundaries, not merely inferred from successful compilation. When a change introduces a new abstraction, lowering path, native facade, or runtime helper, review the emitted Rust shape and keep it warning-clean, rustfmt-friendly, and close to hand-written Rust in ownership, allocation, trait/object use, and module layout. Avoid adding Haxe-facing artifacts, compatibility wrappers, or runtime helpers unless they carry a real typed contract, remove meaningful duplication, or preserve required Haxe semantics; delete scaffolding once its temporary purpose is gone.
- Expose low-level Rust authority through typed Haxe surfaces and generic backend primitives. Native handles, RAII guards, ownership/borrow-shaped references, process/socket/terminal/SQLite primitives, and zero/low-copy data flow should be available through documented externs, metal/native facades, `rust.*` primitives, or compiler-supported abstractions rather than through app-side `Dynamic`, stringly escape hatches, raw generated-Rust edits, or project-specific `__rust__` snippets. If a consumer needs a Rust primitive that haxe.rust cannot express cleanly yet, treat it as a generic compiler/runtime feature gap with tests and docs.
- Systems facade policy: keep portable `sys.*` semantics separate from Rust-native metal facades.
  Do not remove `hxrt` from `sys.io.File`, `sys.io.Process`, sockets, TLS, or DB wrappers merely
  because the underlying Rust primitive is available; those APIs may need runtime handles for Haxe
  compatibility. When direct Rust ownership/no-hxrt behavior is the desired contract, add or extend a
  typed `rust.*` / metal facade with fixtures and output-shape evidence instead of weakening portable
  semantics.
- If typeful, idiomatic Haxe produces poor, noisy, clone-heavy, stringly, or runtime-heavy Rust, treat that as a generic compiler/runtime gap. Fix the lowering, planner, runtime API, or printer with generic tests instead of teaching consumers to contort source code around compiler artifacts.

## Core Guardrails (compiler)

- Keep the pipeline **AST-first**: Builder → Transformer passes → Printer (avoid string-gen except at the printer).
- Prefer typed analysis + passes over regex/string heuristics.
- Framework-first rule: before adding local helpers for concepts a framework already models (module identity, source ownership, build layout, type usage,
  output registration, metadata extraction), check and use the framework/Haxe typed APIs first. Only add a local adapter for the missing boundary,
  keep it narrow, and document why the framework primitive is insufficient there.
- Compile-time-first lowering rule: when typed Haxe information gives a closed answer, encode that answer in Rust AST/lowering instead of making generated code ask `hxrt` at runtime. If an implementation idea starts with a new runtime function, first write down which source/typed information is unavailable to the compiler; without that proof, fix lowering, planner, analysis, or printing instead.
- Lowering ownership order (strict): choose the narrowest layer that can express the contract, in
  this order: (1) typed compiler analysis/lowering that emits direct idiomatic Rust, (2) a narrow
  typed native facade only when Rust lifetimes, ownership, traits, resources, macros, layout, or
  contained `unsafe` cannot be represented cleanly by the current Haxe/compiler surface, and
  (3) `hxrt` only for semantics that genuinely require runtime state or coordination. Do not skip
  directly to a native helper or `hxrt` because it is easier to implement. A runtime solution is a
  rejected design when the compiler already knows the concrete type, field shape, default, subtype
  relation, ownership conversion, module path, or other fact needed to emit the Rust operation.
- Architecture policy: when warnings/regressions come from emitted Rust shape (lowering/printer artifacts),
  fix the compiler pass/lowering logic instead of relying on style-level source workarounds (for example rewriting app code to avoid explicit `return` in lambdas).
- Workaround policy (strict): do not land temporary workarounds. Fix the root cause in compiler/runtime lowering and add or update regression coverage in the same change.
- Single-source convergence policy (strict): when a defect is caused by the same contract, version,
  schema, status, or policy fact being maintained independently across code, config, docs, generated
  artifacts, and workflows, fix the ownership model instead of adding a checker that preserves the
  duplication. Establish one structured authoritative source, generate every mechanically derivable
  consumer from it, and make local/CI validation compare regenerated outputs byte-for-byte. Workflows
  that publish or package those consumers must invoke the same generator and verify the resulting
  artifact from the same source. A standalone cross-file/phrase-scanning guard is allowed only when a
  consumer genuinely cannot be generated; document that constraint, the replacement/deprecation
  condition, and the Beads evidence beside the guard. Do not normalize a synchronization bandage into
  permanent architecture merely because it catches the current symptom.
- Portable mode first; keep a single runtime abstraction point so backends can evolve (e.g., `HxRef<T>`).
- `HxRef<T>` lifecycle gotcha: protect Haxe-visible nullability, shared identity, alias-visible mutation,
  and deterministic cleanup of acyclic payloads, but never treat the current `Arc`/`HxCell`/lock
  representation as API. Strong `HxRef` cycles are intentionally retained without a tracing GC;
  prove that boundary with deterministic `Drop` counters plus weak observers, document explicit
  cycle breaking, and do not add a collector without demonstrated workload evidence. Apply
  `Clone`/`Send`/`Sync`/`'static` bounds only where generated semantics or a real thread/dynamic
  crossing requires them; diagnose unsupported crossing at the Haxe source boundary rather than
  globally banning typed single-thread native values.
- Prefer `import` (and small local `typedef` aliases when appropriate) to avoid verbose fully-qualified type paths in compiler code
  (example: avoid `reflaxe.rust.ast.RustAST.RustMatchArm` when `import reflaxe.rust.ast.RustAST.RustMatchArm` lets you use `RustMatchArm`).
- Prefer strong typing: avoid `Dynamic` in compiler/runtime/examples unless the upstream Haxe API forces it (for example `haxe.Json.parse`, cross-thread message payloads, exception catch-alls).
  When you must cross a `Dynamic` boundary, immediately validate/cast/convert into a typed structure (often a `typedef` schema) and keep the rest of the code typed.
- `Dynamic` policy (strict): use `Dynamic` only when explicitly justified by upstream std/API contracts or unavoidable runtime boundaries.
  Default to concrete `typedef`/class/abstract/external bindings and leverage Haxe’s type system end-to-end.
- `Reflect`/`Any` policy (strict): avoid `Reflect.*` APIs and `Any`-typed payloads in first-party compiler/runtime/example code.
  Prefer typed fields/enums/interfaces; if an upstream/runtime boundary forces `Reflect` or `Any`, keep it tightly scoped and convert back to typed data immediately.
- Compatibility policy (stable releases): avoid silent breakage.
  For intentional breaking changes, require explicit migration notes in docs and linked Beads issues.
- For unavoidable stdlib API boundaries, prefer a descriptive `typedef` alias module (for example `*Types.hx` under `std/rust/_std`)
  so raw `Dynamic` is centralized and documented instead of scattered across implementation files.
- Path privacy policy: never disclose machine-specific absolute local paths (for example `<home>/...`).
  Always use repository-relative paths; for sibling repos, use relative references like `../haxe.elixir.reference`.

## Meta (keep instructions current)

- When a new “gotcha”, policy decision, or workflow trick is discovered, write it down in the **closest scoped `AGENTS.md`** (add one if needed), not just in chat.
- Documentation sync policy: when behavior, profile contracts, public workflow, user-facing status,
  or evidence changes, update the closest relevant docs in the same pass. Check whether `README.md`
  and `docs/faq.md` need a public-facing note; if they do not, record why in the final response or
  Beads evidence rather than silently letting entrypoint docs drift.
- Fix/test policy: after each fix, update tests and/or add a regression test (snapshots, runtime tests, or example test harness), unless an existing test update already covers the behavior change.
- Contract-first TDD policy (strict): for non-trivial compiler/runtime/std behavior changes, start by adding/updating the expected test contract first (snapshot, negative fixture, policy/harness assertion), confirm failure, then implement and re-run targeted checks plus full harness.
  For deterministic report/artifact features, include repeatability assertions (run twice, compare outputs byte-for-byte) in CI guards.
- Public-compatibility graph gotcha: `docs/public-compatibility-manifest.json` schema v2 contains generated type/operation signatures and transitive shipped-type closure for the installed Haxelib class path. Do not hand-edit generated surface fields. After an intentional public Haxe declaration change, run `npm run docs:compatibility:refresh`, review the manifest and generated review-summary diff, and explicitly classify any new non-internal type or operation. The lexical graph is structural evidence only; it never substitutes for typed, semantic, failure-path, or lifecycle evidence required for stable admission.
- Internal-helper boundary rule: application source must not import or fully qualify `haxe.BoundaryTypes.*`, `hxrt.*`, `reflaxe.rust.*`, or `rust._internal.*`; use the public Haxe/std or `rust.*` facade. Keep the canonical roots and exact public exceptions in `reflaxe.rust.analyze.InternalHelperBoundary`, then refresh the compatibility graph. Public facades may resolve transitively to internal handle types, so enforcement must inspect user-authored source spelling rather than followed typedef/type-usage paths. `reflaxe.rust.macros.RustInjection` is the sole current exact exception and remains `raw-experimental`; do not widen the compiler namespace to add another exception casually.
- Independent-consumer QA cadence: after any important complex task or milestone that changes compiler lowering, runtime behavior, std overrides, profile policy, report schemas, generated Rust shape, or metal/portable semantics, run `npm run test:codex-hxrust` when the sibling `codex-hxrust` checkout is available. Treat it as the local app-level pressure test for this compiler, not as a replacement for focused fixtures. If it is skipped, state the reason in the final response or Beads evidence. For small docs-only/mechanical edits, this QA is optional.
- Consumer-app QA boundary: `codex-hxrust` is an independent application that happens to compile
  through this backend, not a compiler-owned test fixture. Do not add haxe.rust-specific scenarios,
  markers, assertions, or workflow wiring to that repository merely to deepen compiler evidence.
  Purpose-built portable/metal runtime contracts belong under this repository's tests or examples.
  The consumer check should invoke the app's normal documented build/test command unchanged; when
  it exposes a generic backend defect, minimize and permanently regress that defect in haxe.rust.
- Escalation visibility rule: when a task crosses the threshold for extended thinking or Oracle review, say so explicitly in chat before escalating.
  Do not silently switch into a deeper-thinking or Oracle-needed path; call out why the escalation is warranted and what question it is meant to resolve.

## Documentation (HaxeDoc)

- For any **vital** or **complex** type/function (compiler, runtime, `std/` interop surface), write **didactic HaxeDoc** using a clear **Why / What / How** structure.
- Documentation threshold rule: do not reserve HaxeDoc only for obviously "big" constructs or artifacts.
  If a type/function/abstract/macro/extern override/metadata pattern is even slightly non-obvious, surprising, or easy to misuse, document it with **Why / What / How** HaxeDoc where it is declared.
  For non-code artifacts that need explanation (generated report schemas, fixture formats, CI-facing outputs), document them at the closest emission point or owning docs page with the same **Why / What / How** standard.
- Be intentionally verbose when it prevents misuse (ownership/borrowing, injection rules, Cargo metadata, `@:coreType`/extern semantics, etc.).
- If you use a **non-trivial Haxe feature** (extern overrides, abstracts, `@:from/@:to`, macros, metadata-driven behavior, `@:native`, `@:coreType`, `@:enum abstract`, typed-ast patterns, etc.), add **comprehensive** HaxeDoc explaining why it exists and how it affects codegen/runtime semantics.
- This repo is a **reference compiler** for backend authors: every non-obvious compiler/runtime/std design decision should be documented where it lives, with explicit tradeoffs and rationale that other Haxe compiler implementers can follow.
- Boundary rule: whenever code crosses an unavoidable dynamic/native boundary (`Dynamic`, `extern`, `untyped __rust__`, runtime FFI), add HaxeDoc that states **why the boundary is required**, what typed shape is expected on each side, and how callers should return to typed code immediately after crossing it.
- Treat docs as part of the stability contract: if behavior changes, update the relevant HaxeDoc and (when applicable) `docs/*.md` + snapshots.

## Prior Art (local reference repos)

- Use `../haxe.elixir.reference` for patterns/APIs we previously used for the Haxe→Elixir target.
- Use `../haxe.elixir.codex` for the original Haxe→Elixir compiler implementation (**read-only; do not modify anything in that repo**).

## Important Lessons (POC)

- CI timing-wrapper gotcha: a shell function that runs a command and then prints elapsed time will
  otherwise return the print command's success status. Always capture and explicitly return the
  wrapped command's exact status, including when the wrapper is called from `if` / `if !` contexts
  where `set -e` is suppressed. Reuse `scripts/ci/timed-command.sh` and keep
  `npm run test:timed-command-failure-propagation` wired into hooks.
- Reflaxe’s `Context.getMainExpr()` is only reliable when the consumer uses `-main <Class>` (don’t rely on a bare trailing `Main` line in `.hxml`).
- Use `BaseCompiler.setExtraFile()` for non-`.rs` outputs like `Cargo.toml` (the default OutputManager always appends `fileOutputExtension` for normal outputs).
- Haxe “multi-type modules” behave like `haxe.macro.Expr.*`: types in `RustAST.hx` are addressed as `RustAST.RustExpr`, `RustAST.RustFile`, etc.
- Keep generated Rust rustfmt-clean: avoid embedding extra trailing newlines in raw items and always end files with a final newline.
- Lint hygiene policy (default): snake_case all emitted members + locals/args, trim code after diverging ops (`throw/return/break/continue`), omit unused catch vars / unused `self_` params, and add crate-level `#![allow(dead_code)]` to keep `cargo build` warning-free.
  - Rust lint gotcha: emit `loop { ... }` instead of `while true { ... }` to stay warning-free under `#![deny(warnings)]` (`while_true`).
  - Stub trait methods that `todo!()` must use `_` argument patterns to avoid `unused_variables` under `#![deny(warnings)]`.
  - Enum-match gotcha: avoid emitting wildcard `unreachable!()` arms when the match is already exhaustive (Rust warns with `unreachable_patterns`).
  - Return-lowering gotcha: never emit `return <expr>` when `<expr>` is statically diverging (`todo!()`, `panic!()`, `hxrt::exception::throw(...)`).
    Emit the diverging expression directly; `return <diverging expr>` triggers Rust `unreachable expression` warnings.
  - Nullable-array indexing gotcha: indexing `Array<Null<T>>` through the checked Rust array API produces
    `Option<Option<T>>`. Lower the Haxe-visible nullable result with typed `Option::flatten()` instead of a
    manual `Some(v) => v, None => None` match; the native combinator is clearer and remains clean under
    rolling-current Clippy.
  - Array-literal coercion gotcha: compile every non-empty literal element once in source order, preserve
    required clone/reuse semantics on that source value, and then coerce it through the literal's unified
    `Array<T>` element contract before emitting `vec![]`. In particular, non-null values in
    `Array<Null<Primitive>>` must become `Some(value)` while source `null` remains `None`.
  - Empty-record gotcha: a zero-field anonymous object must allocate and return its `HxRef<Anon>` directly.
    Do not acquire an empty `borrow_mut()` initialization guard; cleanup can turn the unused guard into
    `let _ = value.borrow_mut()`, which is rejected by Clippy because synchronization guards must not be
    silently discarded.
  - Anonymous-record shape gotcha: never choose an owned/native representation from field names alone.
    In particular, an ordinary Haxe `{ key, value }` record is still a shared mutable reference value and
    must use `HxRef<Anon>` with Haxe reference equality. If a Rust-first API needs an owned pair, expose a
    distinct nominal `rust.*` facade; native map iterators must bridge their items back into the ordinary
    anonymous-record representation.
  - Structural-iterator gotcha: field names and function signatures alone do not make an anonymous value
    a native iterator. Reserve `hxrt::iter::Iter<T>` for Haxe's method-shaped `Iterator<T>` contract
    (`FMethod`); a mutable record with `FVar` callbacks named `hasNext` / `next` remains `HxRef<Anon>`.
    When reading a function-valued anonymous field, clone the typed callback in a bounded read scope and
    drop that guard before invocation so the callback may safely mutate the same record through an alias.
  - Array-backed iterator boundary gotcha: inline `Array.iterator()` and `Array.keyValueIterator()`
    expose typed `haxe.iterators.ArrayIterator<T>` / `ArrayKeyValueIterator<T>` constructors even though
    upstream std modules are not emitted. Classify those finite canonical classes by typed package/module/name
    identity: values map to `hxrt::iter::Iter<T>`, while key/value items map to the ordinary shared
    `HxRef<Anon>` record representation. Iterator argument coercion must clone only when later reads require
    shared cursor reuse. If a source generic exists only inside a structural type whose Rust shape erases it,
    recover the already-specialized Haxe call type and emit an explicit Rust generic argument; applied and
    declaration type-parameter `ClassType` objects may be distinct references, so compare their stable typed
    pack/module/name identity rather than object identity.
  - Lazy nominal-iterator boundary gotcha: do not generalize the finite array lowering into eager
    collection for every class that structurally satisfies `Iterator<T>`. Canonical iterators such as
    `DynamicAccessIterator<T>` snapshot keys but read live values in `next()`, so eager materialization
    changes Haxe semantics. When a generated nominal iterator crosses the method-shaped structural ABI,
    retain the same source object and use the narrow callback-backed `Iter<T>` path; keep ordinary
    vector-backed iterators on the unboxed fast path. Haxe abstract/inlining may hide reusable locals
    behind `TCast`, so ownership checks must peel transparent casts without globally reclassifying
    unrelated expression-shape checks or adding needless last-use clones.
  - Dynamic-runtime gotcha: prefer typed `std/hxrt/*` extern wrappers over raw `untyped __rust__` for runtime APIs returning `Dynamic`
    (example: `haxe.Json.parse`, `sys.thread.Thread.readMessage`) to avoid unresolved monomorph warnings.
  - Unresolved-monomorph fallback policy:
    - User/project code now **errors by default** on unresolved monomorphs (avoid silent runtime-dynamic degradation).
    - Framework/upstream stdlib internals may still fall back to `Dynamic` as a compatibility bridge.
    - Escape hatch: `-D rust_allow_unresolved_monomorph_dynamic`.
    - Std warning audit switch remains: `-D rust_warn_unresolved_monomorph_std`.
  - Unmapped `@:coreType` fallback policy mirrors unresolved monomorphs:
    - User/project code errors by default; framework/upstream std may fallback to `Dynamic`.
    - Escape hatch: `-D rust_allow_unmapped_coretype_dynamic`.
    - Std warning audit switch: `-D rust_warn_unmapped_coretype_std`.
  - Contract diagnostic anchoring gotcha: profile-policy warnings/errors must resolve to **user project source positions**
    whenever possible. Do not anchor contract diagnostics to upstream/framework std module files just because the diagnostic
    message mentions those module names.
- JSON boundary gotcha: do not `cast Json.parse(...)` directly to a typed anonymous structure in app/runtime code. The Rust runtime may return a `DynObject` representation that fails anon downcasts; decode through `Reflect.field` + typed validators at the boundary, then stay strongly typed.
- Dynamic field-update boundary: ordinary runtime `Dynamic` field get/set is supported, but compound assignment and prefix/postfix updates are intentionally unadmitted because the payload's numeric/string kind exists only at runtime. Do not add broad runtime dynamic-operator dispatch or assume a payload type from the RHS; decode to a concrete type at the boundary and keep downstream updates typed. Do not describe ordinary safe-Rust `Dynamic` boxing/downcasts as memory-unsafe: the real costs are runtime type failure, allocation, weaker optimization, and less idiomatic output. Reserve memory-safety warnings for explicit raw/unsafe/native authority.
  - Semantic-diff oracle gotcha: `haxe --interp` is not a valid oracle for threaded `sys.thread.EventLoop` / `haxe.EntryPoint` / `haxe.MainLoop` behavior on this target. Use Rust-target snapshot/example smoke for those contracts and downgrade docs accordingly instead of forcing a false semantic-diff parity claim.
- The generated crate normally includes the bundled runtime crate at `./hxrt` and adds `hxrt = { path = "./hxrt" }` to `Cargo.toml`.
  The exception is proven `-D rust_no_hxrt` output, which must omit the bundled runtime and pass the no-runtime guard.
- Process-environment mutation safety gotcha: Rust cannot generally make process-wide environment
  mutation safe on non-Windows hosts after threads or foreign libraries may read the environment.
  Keep `Sys.putEnv` experimental for stable admission and document it as a provably single-threaded
  startup operation on those hosts. Do not "solve" this with a mutex that guards only hxrt calls;
  foreign/runtime readers do not share that lock. Prefer child-process-specific environment APIs in
  concurrent production code.
- For class instance semantics, the current runtime implementation uses a thread-safe heap
  (`HxRef<T> = Arc<HxCell<T>>` with `RwLock` interior mutability); this representation is not public API:
  - concrete calls use `Class::method(&obj, ...)` where methods take `&HxCell<Class>`
  - polymorphic base/interface calls use trait objects (`HxDynRef<dyn ...>`) and `obj.method(...)` dispatch
- For field assignment on `HxRef` (`obj.field = rhs`), evaluate `rhs` first, then take `borrow_mut()` (otherwise `RefCell` will panic at runtime when `rhs` reads other fields).
- For void Haxe functions, don’t emit a tail expression just because the last expression has a non-void type (e.g. `OpAssign` is typed as the RHS); pass the expected return type into block compilation to decide whether a tail is allowed.
- Escape hatch policy: **apps/examples should not use `__rust__` directly**. Put injections behind Haxe APIs in `std/` and keep examples “pure”.
  - Repo enforcement: `-D reflaxe_rust_strict_examples` (used by `examples/**` and `test/snapshot/**`).
  - Opt-in user enforcement: `-D reflaxe_rust_strict`.
  - Narrow exception: `@:rustAllowRaw` can authorize a single low-level abstraction module under strict boundary enforcement, but it must stay small, documented, and never be used to bypass `metal` / `@:rustMetal` raw-fallback restrictions.
  - `rust.metal.Code.expr/stmt` is a scoped raw bridge, not a normal app-facing DSL. Project-local direct use must be in an owning class tagged `@:rustAllowRaw`; framework/compiler-owned use is allowed via resolved framework roots. This still emits raw `ERaw`, so metal-clean and `@:rustMetal` policy can reject it unless fallback is explicitly enabled for the fixture.
  - `@:rustImpl(..., "fn ...")` body strings are a narrow trait-impl metadata escape for local generated types, not the long-term app authoring model for common Rust trait patterns. Prefer Haxe interfaces, `@:rustGeneric`, typed extern islands, or future typed trait metadata when the Rust shape is common and inspectable.
- `__rust__` can be called without a prefix as `untyped __rust__("...")` (like Elixir’s `untyped __elixir__`). `reflaxe.rust.macros.RustInjection.__rust__` is an optional macro shim that:
  - keeps a typed callable surface (no `untyped` at callsites)
  - supports Reflaxe `{0}` placeholder interpolation with varargs (`RustInjection.__rust__("foo({0})", arg0)`)
- Reflaxe injection gotcha: `TargetCodeInjection.checkTargetCodeInjectionGeneric` returns an empty list when the injected string has no `{0}` placeholders. The compiler must treat that case as “literal injection string”.
- `rust.Ref<T>` / `rust.MutRef<T>` use `@:from` (typically lowered to `cast`) so Haxe typing can pass `T` where refs are expected; codegen must still emit `&` / `&mut` even when the typed expression becomes `TCast(...)`.
  - Ref-arg coercion gotcha: `Dynamic -> Ref<Dynamic>` must not route through a runtime downcast to
    `&Dynamic`; the call-argument layer should borrow the original `Dynamic`. For `Ref<String>`,
    preserve required Rust `String` -> `HxString` bridges in return/helper coercions, and skip
    borrowed inner string wrapping only when the source expression already lowers to
    `hxrt::string::HxString`.
- Rust naming collisions across inheritance must preserve base-field names: assign names in base→derived order and only disambiguate derived names against already-used base names.
- Inheritance method dispatch model: Rust does not “inherit” methods, so subclasses must synthesize concrete Rust methods for non-overridden base methods (compile the base body with `this` dispatch bound to the subclass). This avoids invalid calls like `Base::method(&RefCell<Sub>)` and eliminates `todo!()` stubs in base trait impls.
- Base traits include inherited methods: if `BTrait` includes inherited `A.foo`, then `impl BTrait for RefCell<C>` must implement `foo` even if `B` didn’t declare it; emit base-trait impl methods from the base trait surface (declared + inherited), not just `baseType.fields.get()`.
- Inherited generic-interface gotcha: Haxe records an `implements IFace<T>` edge on the class that declares it; a subclass does not repeat that edge in `ClassType.interfaces`. Because each emitted subclass has its own physical `HxCell<Subclass>` Rust type, collect interfaces across the superclass chain, compose both superclass and interface-parent type arguments in the descendant context, and emit the corresponding trait impl on the child. A trait impl for `HxCell<Base<T>>` cannot satisfy `HxCell<Child>`.
- Field compound-update gotcha: Haxe resolves the receiver and captures the current field value before evaluating the RHS. The RHS may mutate the same field, so concrete and base-typed polymorphic lowering must bind an owned current value first, end any scoped read borrow, then evaluate the RHS and write. A base-typed value is a Rust trait object and must use the generated typed getter/setter contract. For a concrete String field, clone the captured current value only when the RHS may have effects; a local/literal RHS may retain the borrow-based formatting fast path because evaluating that value cannot mutate the receiver. Preserve assigned/old/new expression results and do not add a runtime field registry or dynamic handle for this compiler-known contract.
- Static field-update gotcha: mutable static storage is hidden behind generated lazy-cell getter/setter functions, so a static read is not a Rust lvalue. Lower compound assignments as typed getter → RHS → direct operation → typed setter, with the getter capturing the current value before an RHS that may mutate the same static. Numeric prefix/postfix updates use the same storage contract. Preserve assigned/old/new Haxe expression results; do not add another global registry or runtime API.
- Static property-accessor gotcha: Haxe normalizes `static var value(get,set)` reads, writes, compound assignments, and prefix/postfix updates into typed `get_value` / `set_value` calls before backend expression lowering. Preserve those typed calls and setter-result semantics; do not reinterpret them as raw static storage or add property-specific runtime dispatch.
- Array element-update gotcha: `Array<T>` indexing lowers through typed get/set methods and is not a Rust place expression. For Copy-like numeric compound or prefix/postfix updates and `Array<String>` append assignment, evaluate the array then index once. Compound assignment must also capture the current element before evaluating the RHS, because the RHS may mutate the same slot. Use the existing array storage and typed String-formatting paths, preserve Haxe's assigned/old/new expression result, and avoid cloning a newly appended String when the assignment result is unused. Do not add an array-specific runtime update helper for this compiler-known operation.
- Anonymous field-update gotcha: non-flattened structural objects use the typed `hxrt::anon::Anon` get/set contract. For admitted Copy-like compound updates, capture the object and current typed value before the RHS, end the read borrow, then evaluate and write. This is an ordering fix on the existing anonymous-object boundary, not authority to add generic runtime operator dispatch or admit non-Copy anonymous compound operators.
- `super.method(...)` compiles via per-base “super thunk” methods on the current class (`__hx_super_<base_mod>_<method>`), so base implementations can run with a `&RefCell<Current>` receiver.
- Self-arg naming: treat `TSuper` as “uses receiver” so functions that call `super.*` don’t emit `_self_` but still reference `self_`.
- Accessor naming for backing fields: when a field name starts with `_` (e.g. `_x`), avoid Rust `non_snake_case` warnings and collisions by mapping accessor suffixes to `u<count>_<name>` (e.g. `_x` → `u1_x`), rather than stripping underscores.
- Exceptions/try-catch: implemented via `hxrt::exception` using a panic-id + thread-local payload.
  - `throw v` → `hxrt::exception::throw(hxrt::dynamic::from(v))`
  - `try { a } catch(e:T) { b }` → `match hxrt::exception::catch_unwind(|| { a }) { Ok(v) => v, Err(ex) => ...downcast chain... }`
  - Dynamic-throw gotcha: if the thrown expression is already `Dynamic`, do **not** box it again with `hxrt::dynamic::from(...)`.
    Double-boxing turns a `Dynamic` payload into `Dynamic<Dynamic>` and breaks catch-path reflection/field access.
  - Nested catch-unwind gotcha: panic-output suppression in `hxrt::exception` must be depth-counted (not boolean).
    Inner `catch_unwind` frames can otherwise re-enable panic-hook output too early and leak noisy `Box<dyn Any>` lines
    even when throws are correctly caught by an outer frame (observed with socket `readLine` + server/client wrappers).
  - Current limitation: catch type matching is Rust `Any` downcast (exact Rust type), so catching a subclass from a base-typed trait object isn’t supported yet.
- Reflection registry gotcha: Haxe runtime names use `package + declaration name`; a secondary type's
  containing module is not part of its runtime name (`sample.Secondary`, not
  `sample.Primary.Secondary`). Keep admitted `Type.resolveClass` / `resolveEnum`, dynamic name lookup,
  and enum-constructor listing in a deterministic compiler-generated closed registry. Do not add an
  open-world reflection VM/registry to `hxrt` for declarations the typed compilation already knows.
  Activate the generated registry only when an emitted class body actually uses an admitted dynamic
  lookup; typing an unused upstream std helper must not add dead registry tables to unrelated crates.
  `Class<T>` / `Enum<T>` carriers lower to `u32`; when upstream std keeps such a carrier statically
  typed as `Dynamic`, compiler lowering must downcast the existing box exactly once. Unsupported
  dynamic construction must be rejected at application callsites or throw catchably from retained
  framework branches—never emit `todo!()`, a fake null, or an anonymous-object substitute.
- To include external crates and hand-written Rust modules for demos/interop, use `-D rust_cargo_deps_file=...` + `-D rust_extra_src=...` (the compiler copies `*.rs` into `out/src/` and emits `mod <file>;` in `main.rs`).
- Prefer framework-driven metadata over `.hxml` wiring when possible:
  - `@:rustCargo(...)` declares Cargo deps from Haxe types.
  - `@:rustExtraSrc("path/to/file.rs")` / `@:rustExtraSrcDir("path/to/dir")` lets framework code ship Rust modules without requiring apps to set `-D rust_extra_src=...`.
  - For std overrides that need complex backend-specific setup (for example DB driver connection builders),
    prefer moving Rust-heavy constructors into typed extern modules (`std/hxrt/**` + `@:rustExtraSrc`) rather than inline `untyped __rust__` in Haxe methods.
- Rust module names must avoid keywords (e.g. class `Impl` becomes module `impl_`).
- Nested module output migration: `-D rust_nested_modules` emits package-shaped Rust source paths and nested `mod` declarations. Generated references should use canonical nested `crate::foo::bar::baz::Type` paths; root flat alias modules remain only as a compatibility bridge for handwritten extra Rust/raw snippets that still refer to `crate::<flat_module>::...`.
  - Rust module topology gotcha: a package segment can also be a generated file-backed module (`sys.Sys` plus `sys.io.Stdout`, or `demo.Domain` plus `demo.domain.Widget`). In that case, the parent must be declared as `pub mod sys;`/`pub mod demo;`, and the generated `sys.rs`/`demo.rs` file must declare its child modules. Do not inline a file-backed parent module in `main.rs`; Rust will ignore the sibling file and generated paths such as `crate::sys::Sys` will fail.
- Rust keyword escaping must include reserved keywords like `box` (Rust 2021); keep `RustNaming.KEYWORDS` / extra-src keyword checks in sync.
- Generics: Rust rejects unused type params on structs; emit a `PhantomData` field (e.g. `__hx_phantom`) when a class has type params not referenced by any instance fields.
- Constructors: lift leading `this.field = <arg>` assignments into the struct literal to avoid requiring `T: Default` for generic fields (and to reduce borrow-mut noise).
- Haxe desugaring/inlining introduces `_g*` temporaries; for `Array<T>` (a shared `hxrt::array::Array<T>` handle backed by Rust `Vec<T>` storage), avoid accidental moves by cloning `_g* = <local array>` initializers/assignments.
- Use `Context.getAllModuleTypes()` (not `Context.getTypes()`) to enumerate generated module types for dependency closure / RTTI maps.
- Stdlib emission model (important for “full stdlib parity” work):
  - Parity scope rule: “100% stdlib parity” refers to upstream cross-target std APIs (`Std`, `haxe.*`, `sys.*`, etc.).
    Target-specific namespaces (`cpp.*`, `js.*`, `lua.*`, `php.*`, `python.*`, `hl.*`, `neko.*`, and backend-native `rust.*`) are out of parity scope.
  - The compiler only emits Rust modules for **user project files** and this repo’s `std/` overrides (`isFrameworkStdFile`).
  - Upstream Haxe std files (the default `.../haxe/versions/<ver>/std/`) are *typed* but **not emitted** by default.
  - Consequence: any std API type that appears in emitted signatures (e.g. `sys.io.FileSeek`) must exist under `std/`
    (or the emission filter must be expanded intentionally).
  - Reflaxe convention policy: `haxelib.json` `reflaxe.stdPaths` is the source of truth for target std/support paths.
    Source checkout dev/test hxml must provide those paths before typing; release packaging must delegate the generic
    merge/`.cross.hx` conversion to Reflaxe build. Do not preserve stale source workflows by adding package-layout
    mirrors, symlink mirrors, or macro-time `_std` injection; those hide resolution-order bugs and make compiler code
    depend on deployment layout. Any deviation from Reflaxe conventions must be local, documented, and justified by
    a target-specific Rust runtime/package asset need.
  - Source layout policy: upstream-colliding Rust std overrides live under `std/rust/_std/**/*.hx`, matching Reflaxe-generated compiler layout.
    Dev/test entrypoints must put `std/rust/_std` on the initial classpath; do not rely on macro-time classpath injection for these modules.
  - Source/generated boundary lesson: do not make checked-in source imitate generated or deployed output just to preserve a brittle convenience workflow.
    That couples independent lifecycle stages, creates drift risk, and tends to push release/package concerns into compiler or runtime code.
    Keep the canonical source layout, generated artifact layout, and compatibility workflows distinct; validate each through the workflow that owns it.
  - Compiler-admission vs shipped-API lesson: do not describe a namespace as user-installable just because the compiler can recognize or optimize it.
    A surface is not public package API until its Haxe modules are actually shipped by the owning package or required as an explicit dependency.
    Keep docs and examples clear about whether a type is bundled here, fixture-local, externally supplied, or future family package work.
  - Packaging gotcha: release packaging uses Reflaxe build flow to flatten `reflaxe.stdPaths` into `classPath` (`src/**`), converting
    `_std/*.hx` source overrides into packaged `*.cross.hx` files. Compiler policy should not parse those generated filenames to infer std identity;
    use Reflaxe/Haxe typed module metadata for semantic module identity and use filesystem roots only for source ownership.
  - Path-alias gotcha: framework std detection must canonicalize absolute paths (`FileSystem.fullPath`) before prefix checks, otherwise
    symlink aliases (for example `/var/...` vs `/private/var/...`) can make packaged std overrides look like non-framework files and skip emission.
  - Validation gotcha: `.cross.hx` std override behavior must be validated through a real `-lib reflaxe.rust` install path (`haxelib newrepo` + `haxelib install <zip>`).
    A raw `-cp <pkg>/src` compile is not an equivalent packaging test and can resolve upstream std modules instead.
  - Governance rule: keep `docs/stdlib-provenance-ledger.json` in sync with tracked `std/rust/_std/**/*.hx` files, keep
    `docs/portable-stdlib-allowlist.json` aligned with `test/upstream_std_modules.txt`, and run boundary guards:
    `npm run guard:upstream-stdlib-boundary` + `npm run guard:stdlib-ledger` + `npm run guard:portable-stdlib-allowlist`.
    - Preferred update flow for Tier1 list changes: edit `test/upstream_std_modules.txt`, run
      `npm run stdlib:sync:tier2`, then `npm run stdlib:sync:allowlist`, then run stdlib guards.
- `Std.isOfType` is implemented as a compiler intrinsic (exact-type check via `__hx_type_id`, plus compile-time subtype short-circuit).
- String move semantics: many generated Rust functions take `String` by value; to preserve Haxe’s “strings are re-usable after calls” behavior, callsites currently clone String arguments based on the callee’s parameter types.
- No-hxrt string-shape gotcha: in `metal + rust_no_hxrt` fixtures, even simple Haxe string helpers
  can pull in runtime support. Concrete example: `stdout.length` lowered through
  `hxrt::string::len` in the native-process fixture. For no-hxrt assertions, prefer direct
  comparisons already proven in generated shape (for example `s == ""`) or add a typed `rust.*`
  helper plus an output-shape gate before using a string helper.
- Nullable-string gotcha: portable now defaults to nullable string mode (`hxrt::string::HxString`) while metal defaults to non-null Rust `String` unless `-D rust_string_nullable` is explicitly enabled.
  Treat cross-mode string work as compatibility-sensitive: map key types, `toString` trait bridges, hardcoded `String` paths, and runtime/native API signatures must be checked in both contracts.
  - Concrete breakage pattern: generated code can expect `HxString` while runtime/native APIs still take raw `String`
    (for example `hxrt::array::Array::join`, `sys.io.*.writeString/readLine`, `std::process::Command` args), producing large `E0308` type-mismatch cascades.
  - Interop guardrail: runtime APIs that conceptually accept string separators/paths/labels should prefer flexible signatures (`AsRef<str>`/`&str`) so both `String` and `hxrt::string::HxString` work without callsite churn.
    - Current concrete fix: `hxrt::array::Array::join` is generic over `AsRef<str>` and `HxString` implements `AsRef<str>`.
- Dynamic args: when calling a function expecting `Dynamic` (e.g. `Sys.println(v:Dynamic)`), the compiler boxes non-`Dynamic` args via `hxrt::dynamic::from(...)` and clones non-`Copy` inputs to avoid Rust moves.
- Nullable locals: when a `Null<T>` local is initialized to `null` and the **very next statement** assigns it, codegen elides the initial `None` to avoid Rust `unused_assignments` / `unused_mut` warnings (see `test/snapshot/null_optional_args`).
- Extern bindings: for `extern class` types, `@:native("some::rust::path")` maps the class to a Rust path, and `@:native("fn_name")` maps fields/methods.
  - Gotcha: Haxe may rewrite names and store the original in `:realPath`; for extern fields, prefer the post-metadata identifier (`cf.name`) unless `@:native(...)` overrides it.
- `haxe.io.Bytes` override is `extern` to prevent stdlib inlining; keep its Rust mapping (`HxRef<hxrt::bytes::Bytes>`) as a special-case that must win over generic extern-path mapping.
- Properties vs storage:
  - Only **physical** vars are emitted as Rust struct fields. Non-storage properties (`get/set`, `get/never`, etc.) are lowered to accessor calls.
  - Property assignments must return the setter return value (Haxe semantics), not necessarily the raw RHS.
  - Storage-backed accessors (`default,get` / `default,set`) commonly use `return x = v;` in Haxe; codegen must treat `x` inside `get_x`/`set_x` as direct backing-field access to avoid recursive calls.
  - In inherited method shims, the typed AST may type `this` as the base class; for property/field lowering, treat `this` as `currentClassType` (the concrete class being compiled) to avoid calling base methods with `&RefCell<Sub>` receivers.
- Profiles:
  - Default is portable output.
  - Supported selector values are `-D reflaxe_rust_profile=portable|metal` (no aliases).
  - Profile names are semantic contracts, not output-quality labels:
    - `portable` means Haxe-portable semantics first. Treat it as the default product path, not a slow/safe lane.
    - `metal` means explicit Rust-native authoring semantics, stricter boundaries, and optional reduced/no-HXRT runtime.
    - `idiomatic` is **not** a profile selector. Treat idiomatic Rust output as a quality goal for every profile.
      Portable output should be idiomatic when Haxe semantics permit; metal output should be idiomatic while honoring its Rust-first contract.
  - Architecture slogan: portable by default, Rust-native by opt-in, metal-like performance whenever the compiler can prove Haxe semantics are preserved.
    The optimizer/planner may lower portable abstractions into native Rust representations, but must not silently change the source contract or hide metal fallback where a user explicitly selected `metal`.
    Runtime/tool consumers may choose `metal` first when they need Rust-native behavior, strict host boundaries, or production performance now.
    Treat those cases as pressure to improve generic portable-to-metal convergence where semantics allow, not as permission for project-specific compiler shortcuts.
  - Portable native-import policy: importing native target modules from portable app code emits warnings by default and is recorded in `contract_report.*`.
    `nativeImportHits` preserves the source-text import diagnostic signal; `nativeImportHitsTyped` records user-source typed module usage so aliases and fully-qualified target-native references are visible in deterministic reports.
    Use `-D rust_portable_native_import_strict` to escalate those warnings to errors.
  - Metal policy: `reflaxe_rust_profile=metal` auto-enables strict app-boundary mode (`reflaxe_rust_strict`) so raw app-side `__rust__` is rejected by default.
    Typed framework facades in `src/reflaxe/rust/macros` and `std/rust/metal` remain allowed.
  - Metal string contract: in default non-null string mode, `String` cannot be assigned `null`.
    Use `Null<String>` for nullable values; explicit `== null` / `!= null` checks on strict non-null `String` lower to constant `false` / `true`.
  - Minimal-runtime policy: today, `-D rust_no_hxrt` is metal-only and must remain a hard contract.
    In that mode, do not rely on Cargo-link failures as enforcement; run source/typed-AST no-hxrt eligibility first so Dynamic/reflection/anonymous-runtime/platform blockers fail with stable `runtimeRequirements` reason kinds, then keep the emitted-code no-runtime guard pass (`NoHxrtPass`) active so remaining generated `hxrt` references fail with actionable module-level diagnostics.
    Future capability-driven portable no-hxrt support requires positive portable-facade eligibility fixtures before this policy can be widened.
  - Metal diagnostics gotcha: aggregate `ERaw` fallback diagnostics once per compile (with top modules) instead of warning per transformed module; this keeps fallback signals actionable in large std-heavy builds.
  - Optional formatter hook: `-D rustfmt` runs `cargo fmt --manifest-path <out>/Cargo.toml` after output generation (best-effort, warns on failure).
- TUI testing: prefer ratatui `TestBackend` via `TuiDemo.renderToString(...)` and assert in `cargo test` (see `docs/tui.md` and `examples/tui_todo/native/tui_tests.rs`).
  - Non-TTY gotcha: `TuiDemo.enter()` must never `unwrap()` terminal initialization. If interactive init fails (or stdin/stdout aren’t TTY), it must fall back to headless so `cargo run` in CI doesn’t panic.
  - Rust test harness gotcha: when using a shared `Mutex` in tests, recover poisoned locks with `lock().unwrap_or_else(|e| e.into_inner())` so one failing assertion does not cascade into unrelated `PoisonError` failures.
  - Path privacy gotcha: cleanup/util scripts should log repository-relative paths (not machine-absolute paths) to avoid leaking local filesystem details in terminal/CI logs.
  - Harness linkage gotcha: keep `Harness.__link()` reachable in all compile variants (not only `tui_headless`) so Rust tests that call `crate::harness::*` compile in both dev and CI outputs.
- `@:coreApi` gotcha: core types must match upstream public API exactly. Any extra helpers must be private.
  - Use `@:allow(...)`/`@:access(...)` to make private helpers usable by sibling std types.
  - Backend rule: private members in an `@:allow/@:access` class are emitted as `pub(crate)` in Rust so cross-module calls compile.
- Threading (sys.thread): the current `HxRef<T>` implementation uses `Arc<...>` + locking so admitted
  payloads can cross OS threads when their owning API and generated bounds permit it; the opaque
  handle name is not blanket `Send + Sync` authority for arbitrary native values.
  - `sys.thread.Thread` + core primitives exist; `sys.thread.EventLoop` is runtime-backed. See `docs/threading.md`.

## Testing + CI

- CI health is a hard prerequisite for downstream consumer work such as the codex-hxrust sibling checkout. If CI is reported or observed failing, stop downstream feature work, inspect the failing run, fix the compiler/runtime/tests here first, commit and push the fix, and verify CI is passing or record an explicit equivalent green validation before resuming downstream work.
- Run snapshots locally: `bash test/run-snapshots.sh`
- Run upstream stdlib sweep locally:
  - Tier1 (default): `bash test/run-upstream-stdlib-sweep.sh` (or single-module: `--module haxe.Json`)
  - Tier2 (broader): `bash test/run-upstream-stdlib-sweep.sh --tier tier2`
- Run stdlib boundary/provenance guards locally:
  - `npm run stdlib:audit:candidates`
  - `npm run stdlib:sync:tier2`
  - `npm run stdlib:sync:allowlist`
  - `npm run guard:upstream-stdlib-boundary`
  - `npm run guard:stdlib-ledger`
  - `npm run guard:portable-stdlib-allowlist`
  - `npm run guard:stdlib-candidates`
  - `npm run guard:stdlib-candidate-gap` (defaults to strict zero-gap; override only intentionally via `PORTABLE_STDLIB_CANDIDATE_GAP_MAX`)
  - `guard:stdlib-ledger` also enforces that every provenance-ledger importable module is represented in Tier2; intentional non-importable boundary modules must carry `tier2SweepExcludeReason` in `docs/stdlib-provenance-ledger.json`.
- Run Windows-safe smoke subset locally: `bash scripts/ci/windows-smoke.sh` (same subset used by the Windows CI job).
- Run packaged-install smoke locally: `bash scripts/ci/package-smoke.sh` (build zip, install into local haxelib repo, compile, cargo build).
  - Regression coverage includes a symlinked working-directory compile pass to catch path-alias mismatches when classifying framework std files.
- Run HXRT overhead benchmarks locally: `bash scripts/ci/perf-hxrt-overhead.sh`
  - Refresh baseline intentionally: `bash scripts/ci/perf-hxrt-overhead.sh --update-baseline`
  - Perf harness gotcha: metal benchmark cases use `-D rust_metal_allow_fallback` by design so trend tracking remains available while metal-clean lowering is still in progress.
    Keep the dedicated `hot_loop_no_hxrt` case strict (`-D rust_no_hxrt` without fallback) as the no-runtime parity signal.
- Run metal fallback-count guard locally: `bash scripts/ci/check-metal-fallback-counts.sh`
  - Refresh fallback baseline intentionally: `bash scripts/ci/check-metal-fallback-counts.sh --update-baseline`
  - Metal policy timing: `scripts/ci/check-metal-policy.sh` prints per-case timings and a summary.
    If this stage is slow, inspect repeated optional-fallback checks first; prefer consolidating multiple forbidden-regex assertions for the same fixture/HXML before adding parallelism.
- Update a snapshot’s golden output (after review): `bash test/run-snapshots.sh --case <name> --update`
- Run the full CI-style harness locally (snapshots + all examples): `npm run test:all` (alias for `bash scripts/ci/harness.sh`)
  - Change-gate rule: for any non-trivial compiler/runtime/std/example code change, run the full harness (`npm run check:harness`)
    before marking work complete (unless explicitly scoped to docs-only or user-approved partial validation).
  - Convenience command: `npm run hooks:check:full` runs lint/docs guards plus the full harness.
  - Harness cleanup policy: by default, `scripts/ci/harness.sh` and `scripts/ci/windows-smoke.sh` clean generated `out*` folders and `.cache/*target*` on exit.
    - Keep artifacts intentionally for debugging with `KEEP_ARTIFACTS=1`.
    - Manual cleanup: `npm run clean:artifacts` (outputs only) and `npm run clean:artifacts:all` (outputs + caches).
  - Harness snapshot parallelism: `scripts/ci/harness.sh` runs snapshot cases in bounded parallel batches by default (`HARNESS_SNAPSHOT_JOBS=4`).
    Use `HARNESS_SNAPSHOT_JOBS=1` to force the old serial path; direct `test/run-snapshots.sh` runs remain serial for focused debugging.
    GitHub CI intentionally overrides this to `HARNESS_SNAPSHOT_JOBS=6`; keep the script default more conservative for local machines.
  - Harness package-smoke skip: GitHub CI runs `scripts/ci/package-smoke.sh` as a dedicated step before the full harness, then sets
    `HARNESS_SKIP_PACKAGE_SMOKE=1` for `scripts/ci/harness.sh` to avoid the duplicate package-smoke stage.
    Do not set this flag locally unless package smoke already ran in the same validation flow.
  - Harness stage selector: `HARNESS_STAGES` accepts `all` (default) or comma/space-separated groups:
    `snapshots`, `conformance`, `policy`, `packaging`, `examples`, `parity`.
    Unknown stage names fail fast; keep local `npm run test:all` on the default full suite unless intentionally validating a focused CI shard.
  - CI harness split: GitHub Actions runs harness shards in parallel and keeps `Snapshots + Examples` as the aggregate gate.
    If adding/removing a harness shard, update both the shard job and the aggregate `needs`/result check so a missing shard cannot silently pass.
  - Example CI reuse: `scripts/ci/harness.sh` may reuse a previously compiled developer/example HXML for a CI run variant only when the
    normalized HXML contents match exactly after removing `-D rust_output=...`.
    Keep CI-specific semantic flags (`*_headless`, explicit profiles, native-mode defines, etc.) distinct so those variants still compile separately.
    The harness runs snapshot clippy as a separate curated serial pass so `--case` does not accidentally clippy every snapshot.
- Install the repo pre-commit hook (gitleaks + guards + beads flush): run `bd hooks install` then `npm run hooks:install` (requires `gitleaks` installed)
- Canonical gitleaks entrypoint: use `scripts/security/run-gitleaks.sh` (`npm run security:gitleaks`, `npm run security:gitleaks:staged`).
  Keep pre-commit + CI wired to this shared script to avoid drift in flags/version behavior.
- Local-path leak policy: run `scripts/lint/local_path_guard_staged.sh` in pre-commit and `scripts/lint/local_path_guard_repo.sh`
  in repo-wide guard checks/CI to prevent machine-local paths from entering tracked files.
- Dynamic policy guard: `scripts/lint/dynamic_usage_guard.sh` is part of hooks/CI and fails on any non-allowlisted `Dynamic` mention in first-party `*.hx`/`*.cross.hx` files.
  Keep intentional compatibility/runtime boundaries in `scripts/lint/dynamic_allowlist.txt` and remove avoidable `Dynamic` elsewhere.
  - Scan model: the guard is comment-aware; comment-only/doc-text mentions are ignored so the allowlist tracks code boundaries, not prose churn.
  - Compiler boundary-literal pattern: keep the unavoidable Haxe dynamic type-name literal centralized in
    `RustCompiler.dynamicBoundaryTypeName()` and route lookups/comparisons through it to prevent scattered allowlist churn.
  - Allowlist strictness: file-scoped entries must include an inline `# FILE_SCOPE_JUSTIFICATION: ...` comment in
    `scripts/lint/dynamic_allowlist.txt`; otherwise the guard fails during parsing.
- Deprecated-define guard: `scripts/lint/deprecated_define_guard.sh` is part of hooks/CI and fails if removed selectors/defines
  (`reflaxe_rust_profile=idiomatic|rusty`, `rust_async_preview`, `rust_profile_contract_report`, `rust_hxrt_plan_report`)
  reappear outside explicit migration/negative-test allowlisted files.
  It also fails on stale naming artifacts (`idiomatic_profile`, `async_preview_retry`, `profile_contract.*`, `hxrt_plan.*`)
  to enforce hard-cutover naming.
- Runtime gotcha: snapshots embed `runtime/hxrt/**` into `test/snapshot/**/intended/hxrt/`, so any change under `runtime/hxrt/` requires `bash test/run-snapshots.sh --update` to keep goldens in sync.
- Snapshot runner gotcha: many snapshot crates share the same crate name (`hx_app`), so `test/run-snapshots.sh` must isolate `CARGO_TARGET_DIR` per case/variant
  (using a shared base cache) to avoid binary collisions and incorrect `stdout.txt` comparisons.
- `cargo hx` wrapper gotcha: when a smoke/test run compiles both the repo wrapper tool (`tools/hx`) and generated-template wrappers with a shared `CARGO_TARGET_DIR`,
  Cargo can reuse a binary compiled with the wrong `CARGO_MANIFEST_DIR` and resolve `scripts/dev/cargo-hx.sh` to the template copy.
  Keep wrapper-target dirs isolated for mixed-root/template checks (see `scripts/ci/template-smoke.sh`).
- Docs tracker gotcha: for progress-doc drift checks, compare docs before/after `npm run docs:sync:progress` (not against git HEAD) so checks work in dirty worktrees too.
- Docs tracker source-of-truth gotcha: generated tracker docs must derive readiness/baseline status from explicit milestone/gate issues,
  not from umbrella roadmap epics. Umbrella epics stay open for planning and will make generated status falsely read as `open`.
- Docs tracker guard policy: `npm run docs:check:progress` must fail on stale tracker-backed docs even when `bd` is unavailable (fallback source is `.beads/issues.jsonl`, so keep tracker status commits synced via `bd sync`).
- Semantic-confidence gotcha: `scripts/ci/generate-semantic-confidence-summary.js` discovers cases with `git ls-files`, so plain `npm run docs:check:evidence`
  can report stale counts in a dirty worktree where new snapshot directories are still untracked.
  For intended-stack validation before staging, use a temporary full index (`GIT_INDEX_FILE=... git add -A`) and run `npm run docs:check:evidence` under that index.
  Once cases are staged, the repo pre-commit hook requires both generated summary artifacts to be staged, free of unstaged edits, and byte-for-byte current.
- Disk-space gotcha: full snapshot regeneration and full harness runs can consume many GB in `test/snapshot/**/out*`, `examples/**/out*`, Cargo caches/registries, and `.cache/examples-target`.
  If you hit `No space left on device`, run `npm run clean:artifacts:all` before re-running, then regenerate snapshots.
  When adding a new harness stage that writes ignored generated outputs or Cargo target/cache roots,
  update `scripts/ci/clean-artifacts.sh` in the same change so `npm run clean:artifacts:all`
  actually restores the repo to a no-generated-artifacts state after full validation.
- Prefer DRY snapshot cases: use multiple `compile.<variant>.hxml` files in the same `test/snapshot/<case>/`
  directory (and `#if <define>` shims when needed) rather than duplicating snapshot directories for each profile.
  - Convention: `compile.hxml` → `out/` + `intended/`; `compile.metal.hxml` → `out_metal/` + `intended_metal/`.
- Pre-push directive: keep `main` green by running the closest local equivalent of CI before `git push`:
  - `npm ci --ignore-scripts --no-audit --no-fund`
  - `bash test/run-snapshots.sh --clippy` (runs curated clippy checks on a small subset of snapshot crates)
  - `bash test/run-upstream-stdlib-sweep.sh` (Tier1 curated upstream std imports under `-D rust_emit_upstream_std`)
  - `bash test/run-upstream-stdlib-sweep.sh --tier tier2` (blocking CI gate for broader parity coverage)
  - `bash scripts/ci/perf-hxrt-overhead.sh` (soft-budget warnings + artifact report)
  - `cargo fmt && cargo clippy -- -D warnings`
  - Smoke-run any examples you touched (e.g. `(cd examples/tui_todo && haxe compile.hxml && (cd out && cargo run -q))`)
- CI runs:
  - `test/run-snapshots.sh` (runs `cargo fmt` + `cargo build -q` per snapshot)
  - Keep `scripts/ci/check-metal-policy.sh` regex expectations in sync with emitted contract diagnostics and wire every `test/negative/metal_*` fixture into that script so metal subset enforcement cannot silently drift.
  - `test/run-upstream-stdlib-sweep.sh` (Tier1 per-module actionable compile/fmt/check for upstream std modules)
  - `test/run-upstream-stdlib-sweep.sh --tier tier2` (blocking CI gate for broader parity coverage)
  - `guard:stdlib-candidates` (parity-gap check; weekly + main CI upload `portable-stdlib-candidates` artifact)
  - `guard:stdlib-candidate-gap` (weekly hard budget check; keep default budget at 0 unless an approved transition explicitly sets an override)
  - `scripts/ci/package-smoke.sh` validates the packaged artifact via isolated local `haxelib` install + Rust build (including symlink-cwd alias regression).
  - `scripts/ci/perf-hxrt-overhead.sh` benchmarks HXRT overhead (`hello`/`array`/`hot_loop`/`hot_loop_inproc`/`hot_loop_no_hxrt` vs pure Rust baselines + chat profile spread) and emits soft-budget warnings + artifacts.
  - `scripts/ci/template-smoke.sh` scaffolds `templates/basic` via `scripts/dev/new-project.sh` and executes the full task-HXML matrix (`compile.build`, `compile`, `compile.run`, `compile.release`, `compile.release.run`).
  - CI shell-tooling compatibility: scripts must not hard-require `rg`; always keep a `grep`/`find` fallback.
    - Fallback test knob: set `REFLAXE_NO_RG=1` to force non-`rg` paths during local validation.
    - Local zsh wrapper gotcha: do not store command exit codes in a variable named `status`;
      zsh exposes `$status` as read-only, so use `hook_status`, `exit_code`, or similar instead.
  - `scripts/ci/harness.sh` runs snapshots, conformance checks, metal boundary policy, fallback/idiom count guards, upstream stdlib sweep, package smoke, template smoke, then compiles all non-CI example variants (`compile*.hxml`, excluding `*.ci.hxml`) and runs every CI variant present (`compile*.ci.hxml`, fallback `compile.hxml` when no CI file exists), including `cargo test` + `cargo run`.
  - `scripts/ci/windows-smoke.sh` runs on `windows-latest` and validates a Windows-safe subset (fmt/clippy + `hello_trace`/`sys_io` snapshots + `examples/sys_file_io` + `examples/sys_net_loopback`).
  - Weekly CI evidence summary steps are `if: always()` and must tolerate missing evidence artifacts when an earlier harness stage fails before generating them.
    Avoid escaped `\n` heredocs inside shell command substitutions in workflow YAML; use a normal literal-block heredoc or script file so GitHub's generated shell is valid Bash.
    For long Cargo-heavy weekly jobs, keep Cargo network retries enabled and disable HTTP multiplexing in CI to reduce transient crates.io HTTP2 failures.

## Build (native)

- Default: compiling with `-D rust_output=...` generates Rust and runs `cargo build` (debug) best-effort.
- HXML default policy: new user-facing `compile*.hxml` files should compile+run by default via `-D rust_cargo_subcommand=run`
  (and usually `-D rust_cargo_quiet`), unless the file is explicitly CI/headless/build-only scoped.
- The generated Cargo crate emits a minimal `.gitignore` by default (opt-out: `-D rust_no_gitignore`).
- Codegen-only: add `-D rust_no_build` (alias: `-D rust_codegen_only`).
- Deny warnings (opt-in): add `-D rust_deny_warnings` to emit `#![deny(warnings)]` in the generated crate root.
- Release: add `-D rust_build_release` / `-D rust_release`.
- Optional target triple: `-D rust_target=x86_64-unknown-linux-gnu` (passed to `cargo build --target ...`).
- Cargo/tooling knobs (for parity with other targets’ tool scaffolding):
  - `-D rust_cargo_subcommand=build|check|test|clippy|run` (default: `build`)
  - `-D rust_cargo_features=feat1,feat2`
  - `-D rust_cargo_no_default_features`, `-D rust_cargo_all_features`
  - `-D rust_cargo_locked`, `-D rust_cargo_offline`, `-D rust_cargo_quiet`
  - `-D rust_cargo_jobs=8`
  - `-D rust_cargo_target_dir=...` (sets `CARGO_TARGET_DIR`)

## Tooling (lix)

- This repo uses **lix** for a pinned Haxe toolchain (see `.haxerc`).
- `haxe_libraries/reflaxe.rust.hxml` is a self-referential config so `-lib reflaxe.rust` works in `test/**` and `examples/**` without `haxelib dev`.
- `test/run-snapshots.sh` prefers the project-local Haxe binary at `node_modules/.bin/haxe` when available (override with `HAXE_BIN=...`).
- Dev watcher policy: `scripts/dev/watch-haxe-rust.sh` owns a session-local Haxe compile server in watch mode (`haxe --wait` + `--connect`) for fast incremental rebuilds.
  - Keep server ownership scoped to the watcher session (avoid attaching to external long-lived servers by default).
  - `--once` intentionally compiles directly by default.
  - Disable server mode explicitly with `--no-haxe-server` or `HAXE_RUST_WATCH_NO_SERVER=1` when debugging cache-related behavior.
  - Watch-mode cargo gotcha: normalize compile phase by mode (`run/test` force `-D rust_no_build`, `build` forces `rust_cargo_subcommand=build`) so task-style `.hxml` defaults (for example `rust_cargo_subcommand=run`) do not cause duplicate cargo invocations.
- Cargo task driver: use `cargo hx ...` (alias for `scripts/dev/cargo-hx.sh`) as a project-local runner (`compile -> cargo action`) instead of proliferating task-specific `compile.*.hxml` files.
  - Convenience aliasing: `examples/.cargo/config.toml` keeps `cargo hx ...` working from inside any `examples/<name>/` directory without extra flags.
  - Template parity: generated projects from `scripts/dev/new-project.sh` must include a local `cargo hx` alias/driver too (`templates/basic/.cargo/config.toml` + `templates/basic/scripts/dev/cargo-hx.sh`).

## Releases

- GitHub Actions:
  - `.github/workflows/ci.yml` runs on PRs/pushes to `main`.
  - The normal `release` job is the final job in `.github/workflows/ci.yml`, runs only for a push to
    `main`, depends on the required jobs from that same run, checks out `github.sha`, and alone gets
    `contents: write`.
  - `.github/workflows/release-repair.yml` is manual existing-tag repair only. It must never derive a
    version, create/move/delete a tag, or fall back from the supplied tag to `main`.
  - `.github/workflows/rustsec.yml` runs `cargo audit` on a schedule.
  - Workspace gotcha: exclude `examples/` + `test/` + `.cache/` from the root workspace so `cargo fmt/build` works inside generated `*/out/` crates during snapshot and template-smoke runs.
- Packaging policy: `scripts/release/package-haxelib.sh` delegates the generic layout work to the vendored Reflaxe `Run build` flow, which merges `reflaxe.stdPaths` into `classPath`, converts `_std/*.hx` sources into packaged `*.cross.hx`, and sanitizes `haxelib.json` (remove `reflaxe` field). The script still ships target-required `runtime/` + `vendor/`.
- Release toolchain gotcha: the CI `release` job and repair workflow must install the pinned lix Haxe
  toolchain before packaging. The local artifact plugin executes `scripts/release/package-haxelib.sh`,
  which runs Reflaxe build through `haxe`/`haxelib`.
  Keep this setup aligned with the CI package-smoke Haxe setup; `npm ci --ignore-scripts` alone is insufficient because it skips lix postinstall and can leave `haxelib` without its Neko runtime.
- Conventional commits are required on `main` so semantic-release can compute the next version.
  - Use `feat:` for minor and `fix:` for patch. On ungraduated `0.x`, `feat!:` /
    `BREAKING CHANGE:` deliberately advances the minor line; after stable approval it advances the
    major line normally.
  - GitHub Release notes are the canonical changelog. The locked release-notes generator must be
    exercised through `test:release-notes` with feat/fix/perf, scoped, bang-header, and breaking-footer
    commits. Do not assume that a preset shared with the commit analyzer has a compatible writer;
    `conventionalcommits` 10.2.1 with release-notes-generator 14.1.1 emitted heading-only releases.
- Small release-protocol rule (strict): normal publication tags the exact CI-tested commit. Do not
  add release-time Git commits, tracked version/changelog updates, generated patch-version prose,
  package-version-dependent configuration loading, or a privileged `workflow_run` publisher.
- `release-manifest.json` owns policy only. Major zero is initial development; every stable major
  owns its own Bead/date approval; missing majors and disabled channels fail closed. Strict parsing
  belongs to the locked standard `semver` dependency, not a custom regex.
- Tracked package/HXML versions are development sentinels. Exact versions are injected only into the
  staged Haxelib package and bound to the tag/source SHA in `release-metadata.json`.
- Release artifact rule (strict): build the complete package twice, require byte-identical output,
  validate the full ZIP contract, run package smoke against that exact ZIP, and compare hosted
  state/size/SHA-256 to the approved local ZIP and checksum. Published releases and remote version
  tags are immutable; never move/delete a remote version tag to recover.
- If a valid tag lacks a complete GitHub Release, use existing-tag repair from `docs/release.md`;
  never advance the version merely to escape partial publication.
- Treat `docs/release-reference-architecture.md` as the reference contract for sibling compiler
  repositories. Reuse its ownership and lifecycle invariants, but inventory and adapt each repo's
  version surfaces, package format, stable-graduation evidence, and application pressure test rather
  than copying haxe.rust-specific paths blindly.
