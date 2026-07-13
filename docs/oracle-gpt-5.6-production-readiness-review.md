# GPT-5.6 Pro deep production-readiness review

Prepared for the independent `reflaxe.rust` production-readiness, architecture, and stable-1.0 audit.

Paste the complete **Review prompt** section into GPT-5.6 Pro after attaching the material listed under **Upload checklist**.

## Review prompt

### Deep production-readiness and stable-1.0 audit: reflaxe.rust

Act as an independent senior compiler architect and production-readiness reviewer with expertise in:

- Haxe compiler semantics and typed AST transformations
- Rust ownership, safety, concurrency, async, performance, and library design
- language-runtime and standard-library implementation
- release engineering, artifact provenance, and software supply-chain security
- compatibility policy and long-lived public APIs
- production adoption of cross-language compilers

This is an adversarial, evidence-first review. Do not implement changes. Inspect the supplied source, tests, generated-output contracts, workflows, package contents, and documentation, then provide an actionable disposition.

#### Primary objective

Determine whether reflaxe.rust is:

1. usable for bounded production workloads today;
2. ready to make a stable 1.x compatibility promise;
3. architecturally suitable as a reference Haxe-to-Rust compiler;
4. progressing credibly toward its long-term “Bun-class workload” quality bar.

These are four different judgments. Do not conflate them.

A stable 1.0 release is not urgent. A NO-GO verdict is acceptable. Conversely, do not require universal Haxe parity, every Rust ecosystem feature, or every operating system before permitting a carefully bounded production or stable contract.

For every gap, decide whether it must be:

- fixed for any credible production use;
- fixed only if the affected surface is admitted to the stable contract;
- resolved by explicitly qualifying or excluding that surface;
- deferred as optional post-1.0 work.

Avoid turning the audit into a feature wishlist.

#### Repository and evidence snapshot

Primary repository:

- Project: `reflaxe.rust`
- Public repository: https://github.com/fullofcaffeine/reflaxe.rust
- Reviewed commit: `a91f3cefca9d33cf9668cdceb9267a164b688868`
- Target: Haxe 4.3.7 to Rust through Reflaxe
- Current release: `v0.85.18`
- Release: https://github.com/fullofcaffeine/reflaxe.rust/releases/tag/v0.85.18
- Current-head CI: https://github.com/fullofcaffeine/reflaxe.rust/actions/runs/29272013652
- Latest scheduled weekly evidence: https://github.com/fullofcaffeine/reflaxe.rust/actions/runs/29250182711

The current release artifact is:

- Filename: `reflaxe.rust-0.85.18.zip`
- Size: 688,087 bytes
- SHA-256: `42df24e23dd808f52f8f2e3e7b26c8667e5e26c4f6b73e8a86438de52319e34d`
- The sidecar, hosted digest, package provenance metadata, tag, and source commit were reported as agreeing.
- The GitHub Release was reported as immutable.

The current-head CI is green across the repository’s required compiler, snapshot, semantic, policy, packaging, example, Tier-2, performance, security, Windows-smoke, minimum-Rust, current-Rust, and release jobs. Dependency review is skipped on push events by workflow design.

The most recent scheduled weekly run is green, but it tested compiler commit:

`bededc3949c9672cb3841acdd636864b3dd51554`

It therefore does not by itself establish scheduled-run evidence for the newer reviewed commit. Determine whether a current-head weekly run is necessary before a 1.0 admission decision or merely before declaring a particular release candidate.

An independent consumer is supplied as secondary evidence:

- Project: `codex-hxrust`
- Public repository: https://github.com/fullofcaffeine/codex-hxrust
- Reviewed consumer commit: `7b590d2e18e15777928ef58ff546799d3500f612`
- It has been locally regenerated, Cargo-checked, and Cargo-tested against the current compiler in portable and metal profiles.

`codex-hxrust` is a real, independent application under development. It is not the compiler’s private QA fixture and must not become coupled to compiler internals. Use it only as application-level integration pressure. Missing Codex application functionality is not automatically a compiler defect. Compiler-specific regressions belong in `reflaxe.rust` fixtures, examples, or end-to-end tests.

Current reported evidence inventory includes approximately:

- 138 compiler snapshots
- 34/34 portable semantic-difference cases
- 2/2 warning-clean representative cases
- 3 curated Clippy lanes
- 100 Tier-1 standard-library modules
- 224 Tier-2 compile-only modules
- 10 API probes
- 174 inventoried shipped Haxe types
- 11 public member families
- 18 compiler-owned metadata names
- 55 consumer-facing defines
- 4 JSON report contracts
- 6 generated-artifact contracts
- 749 closed Beads and no currently open Beads

Treat all counts, closed issues, and green CI as evidence, not proof of correctness or readiness.

A complete local `npm run test:all` and repository hooks were also reported green on the reviewed state.

#### Intended product boundary

The compiler has two principal profiles:

- Portable: preserve supported Haxe semantics, using `hxrt` where necessary.
- Metal/native: expose typed Rust-oriented facilities and more direct Rust behavior.

The canonical profile metadata is `@:rustMetal`. `@:haxeMetal` is a deprecated compatibility alias and should not be mistaken for the canonical spelling.

The product does not claim blanket support for every Haxe program, every `sys.*` behavior, every Rust feature, or every platform. Current public wording describes a production-capable 0.x preview on validated lanes.

Platform/toolchain posture:

- Haxe: 4.3.7
- Generated Cargo edition: Rust 2021
- Minimum tested Rust: 1.96.0
- A current-stable Rust lane is also exercised
- Node: 22.14.0 for the current release workflow
- Linux: primary/full CI platform
- Windows: curated smoke-CI lane
- macOS: local contributor validation only, not a CI-backed support lane

The long-term goal is for well-typed Haxe to generate readable, warning-clean, efficient, memory-safe, idiomatic Rust suitable for demanding production applications. “Bun-class” is a workload-quality pressure test, not a commitment to build BunHx and not a claim that every Bun feature must exist before 1.0.

#### Non-negotiable architectural principles to assess

Do not recommend violating these principles merely to make a test pass:

1. Well-typed Haxe is the source-language contract.
2. Compiler design is AST-first: builder, typed transformations/passes, then printer.
3. Prefer compile-time lowering when the typed AST, metadata, or literals provide a closed answer.
4. Expanding `hxrt` is a last resort. It is appropriate for genuinely runtime phenomena such as identity, shared ownership, reflection/Dynamic payloads, exceptions, threading, platform resources, or non-clone handles—not facts already known by the compiler.
5. Native Rust facade helpers must remain narrow typed islands, not become a second runtime.
6. Generated Rust quality is a first-class output: readable, rustfmt-friendly, warning-clean, reasonably idiomatic, and close to hand-written Rust performance where Haxe semantics permit.
7. Portable `sys.*` semantics and direct Rust-native `rust.*` ownership facades are separate contracts.
8. Applications and examples should not be taught to work around compiler defects with `Dynamic`, raw Rust snippets, generated-file edits, or compiler-specific source contortions.
9. Fix compiler/runtime root causes and add focused regressions. Do not recommend temporary application-side patches.
10. `codex-hxrust` remains an independent application; compiler-owned QA belongs in this repository.

If you conclude one of these principles is itself unsound, explain the concrete counterexample and propose the smallest replacement principle.

#### Compatibility model to inspect

The repository proposes exactly four compatibility classes:

- Stable candidate
- Qualified stable candidate
- Experimental
- Excluded/internal

Deprecation is an orthogonal lifecycle status, not a fifth class.

The public compatibility manifest and review attempt to inventory shipped types, public member families, metadata, defines, reports, generated artifacts, package layout, profiles, and toolchain boundaries.

Review whether:

- the inventory is complete and mechanically guarded against drift;
- the four classes are applied truthfully;
- the qualification of each surface is precise enough to enforce;
- transitive public types such as handles and result types are classified;
- experimental surfaces cannot be promoted accidentally;
- deprecated stable surfaces remain protected for the appropriate major;
- changes to defaults, metadata grammar, generated paths, Cargo behavior, reports, diagnostics, platform floors, and toolchain floors are treated correctly;
- the proposed minimum 1.0 contract is coherent and useful rather than merely small;
- significant implementation detail has accidentally been frozen as API;
- public API has been labeled internal merely because maintainers intend consumers not to import it.

A gap does not necessarily block 1.0 if the surface can truthfully remain experimental, qualified, or excluded.

#### Release architecture to verify proportionately

The release design was intentionally simplified. Its intended invariant is:

```text
tested commit
→ deterministic artifact built from that commit
→ tag that exact same commit
→ immutable hosted release containing the exact artifact
→ hosted digest verification
```

It deliberately avoids creating and pushing a separate release commit during publication.

The repair workflow should accept only an existing immutable version tag, rebuild or recover the deterministic artifact for that tag, and complete an interrupted GitHub Release. It must not derive a new version, tag an arbitrary branch, move a remote tag, or silently substitute different bytes.

Verify this implementation, but do not let release mechanics dominate the entire compiler/product audit unless a real release blocker exists.

#### Files and areas to prioritize

Start with:

- `AGENTS.md`
- `prd.md`
- `README.md`
- `package.json` and lockfiles
- `haxelib.json`
- `release-manifest.json`
- `release.config.*`
- `.github/workflows/**`
- `docs/production-readiness.md`
- `docs/semver-release-posture.md`
- `docs/pre-1.0-compatibility-review.md`
- the machine-readable compatibility manifests
- `docs/feature-support-matrix.md`
- `docs/semantic-confidence-summary.*`
- `docs/vision-vs-implementation.md`
- `docs/systems-environment-posture.md`
- `docs/concurrency-posture.md`
- `docs/rust-toolchain-policy.md`
- `docs/release.md`
- `docs/release-reference-architecture.md`

Then inspect:

- `src/reflaxe/rust/**`
- `runtime/hxrt/**`
- `std/**`
- native-facade manifests and helpers
- compiler snapshots and runtime/semantic fixtures
- package and release scripts
- performance and determinism harnesses
- examples
- `vendor/reflaxe/**`, including its patch/provenance documentation
- the actual release ZIP
- the filtered `codex-hxrust` consumer evidence

Documentation states intended contracts; it is not proof. Prefer implementation and executable evidence when they disagree.

#### Required audit dimensions

##### 1. Product definition and public claims

Assess whether the product describes a coherent supported workload rather than relying on phrases such as “ordinary supported Haxe.”

Determine:

- what a production user can safely build today;
- what is merely compile-covered;
- what is runtime/semantic-tested;
- which target/platform/toolchain combinations are actually supported;
- whether README, FAQ, matrices, release posture, and package documentation agree;
- whether the project truthfully distinguishes controlled production use, 1.0 API stability, broad parity, and aspirational quality.

Propose exact replacement public wording if current claims are too broad or too weak.

##### 2. Stable API and SemVer contract

Review public Haxe APIs, metadata, defines, reports, generated layout, package layout, Cargo behavior, profile selection, diagnostic contracts, and native facade boundaries.

For each significant contract family, recommend one of:

- Admit to 1.0
- Admit with an explicit qualification
- Keep experimental
- Exclude/internalize
- Require additional evidence before deciding

Check migration and deprecation rules, including changes that may appear additive but break exhaustive matching or generated-code consumers.

##### 3. Compiler architecture

Assess:

- AST-first discipline and remaining string/raw generation;
- pass responsibilities, ordering, invariants, and determinism;
- framework/Reflaxe API usage versus duplicated local machinery;
- lowering ownership and type propagation;
- module/path/name planning;
- report and generated-artifact ownership;
- error handling and diagnostic anchoring;
- whether compiler code contains hidden global state or ordering dependence;
- maintainability and auditability.

`src/reflaxe/rust/RustCompiler.hx` is currently very large, approximately 18,000 lines. Determine whether this is merely inconvenient or a concrete correctness/change-risk problem. If decomposition is warranted, propose dependency-oriented seams rather than a cosmetic file split.

##### 4. Haxe semantic correctness

Inspect evidence and likely gaps for:

- nullability and optional values;
- generics, monomorphization, and core types;
- classes, inheritance, interfaces, method dispatch, `super`, and accessors;
- closures, captures, evaluation order, and side effects;
- anonymous structures and reflection boundaries;
- `Dynamic`, `Any`, and runtime downcasts;
- exceptions, nested catches, and typed catch behavior;
- iterators and collection semantics;
- strings, Unicode, paths, and OS strings;
- enums, abstracts, GADT-style patterns, and exhaustive matching;
- Haxe standard-library and `sys.*` contracts;
- deterministic differences explicitly documented as target-specific.

Distinguish compile coverage from semantic parity.

##### 5. Rust safety, ownership, and failure behavior

Audit generated Rust and `hxrt` for:

- ownership and borrowing correctness;
- `HxRef`, shared ownership, interior mutability, and lock/borrow behavior;
- `Send`/`Sync` assumptions;
- potential deadlocks, poisoning, reentrancy, or lock-order hazards;
- lifetime or aliasing assumptions at native boundaries;
- cancellation and resource cleanup;
- partial initialization and panic safety;
- use of `panic!`, `unwrap`, `expect`, `todo!`, and unreachable branches.

Search results suggest such constructs exist in runtime/compiler/native-helper code. Do not label every occurrence a bug. Determine whether each concerning path is reachable through an admitted surface and whether it represents:

- required Haxe exception/failure semantics;
- an intentionally excluded invariant violation;
- an avoidable process-level panic;
- possible data corruption, deadlock, unsoundness, or denial of service.

Explicitly identify any P0/P1 memory-safety, data-loss, concurrency, or process-crash risks.

##### 6. Generated Rust quality

Inspect representative portable, metal, nested-module, no-hxrt, async, concurrency, systems, interop, and generic output.

Assess:

- readability and idiomatic shape;
- unnecessary cloning, allocation, boxing, dynamic dispatch, or runtime calls;
- algorithmic regressions hidden behind acceptable syntax;
- Rust warnings, rustfmt, and Clippy quality;
- module/crate organization;
- Cargo dependency minimality and feature inference;
- error propagation and stack traces;
- source-level diagnostic/debuggability;
- whether output remains understandable to Rust engineers during incidents;
- whether compiler output reasonably approaches hand-written Rust where Haxe semantics allow it.

Identify root causes in lowering/planning/runtime design, not source-level workarounds.

##### 7. Runtime scope and no-runtime boundaries

Assess whether `hxrt` remains a necessary, narrow semantic runtime or is becoming a broad convenience layer.

For every material runtime subsystem, ask:

- could the typed compiler have emitted the answer directly;
- does the runtime own genuine dynamic/stateful/platform behavior;
- is the helper narrowly typed and low overhead;
- is feature inference correct and deterministic;
- do `rust_no_hxrt` and metal contracts truthfully omit the runtime where promised;
- are runtime and native-facade ownership boundaries enforced mechanically.

##### 8. Standard library and systems behavior

Review admitted behavior for:

- files, directories, paths, environment, and process APIs;
- threads, mutexes, locks, channels, event loops, and pools;
- sockets, HTTP, TLS, SQLite, and MySQL compile/runtime boundaries;
- blocking behavior, timeouts, partial reads/writes, EOF, errors, and cleanup;
- platform-specific behavior;
- conversion between Rust failures and Haxe-visible failures;
- deterministic Cargo dependency/feature selection.

Do not demand broad TLS, DB, or networking coverage if the current qualified contract is accurate. Flag misleading breadth or missing production-critical behavior inside the declared lane.

##### 9. Async and concurrency

Assess runtime creation, nested runtimes, task ownership, cancellation, wakeups, backpressure, shutdown, panic propagation, cross-thread payloads, and resource release.

Determine whether the current async/concurrency APIs are safe and useful within their declared qualification and what must remain experimental.

##### 10. Interop, native facades, metadata, and Cargo

Review:

- typed extern/native facade design;
- raw Rust authority and containment;
- trait/generic/derive metadata;
- Cargo dependency declarations and conflict resolution;
- extra-source ownership and module inclusion;
- custom Cargo manifest boundaries;
- path traversal, symlinks, name collisions, and unsafe archive inputs;
- native-helper dependencies and hidden `hxrt` coupling;
- whether application code can import implementation helpers claimed to be internal.

Prefer typed, inspectable contracts over stringly passthroughs, but recognize that bounded escape hatches can be legitimate experimental API.

##### 11. Performance and footprint

Assess whether current benchmarks establish meaningful claims about:

- runtime speed;
- allocations and cloning;
- binary size and runtime footprint;
- startup;
- generated-code size;
- compiler/build time;
- incremental developer workflow;
- regression thresholds and noise handling.

Check whether benchmarks compare equivalent semantics and whether they can detect realistic regressions. Do not require benchmarking every feature.

##### 12. Platforms and toolchains

Review the minimum Rust policy, current-stable lane, Haxe pin, Node pin, Linux/Windows/macOS wording, reproducibility, and update policy.

Determine whether:

- Rust 1.96.0 is actually enforced;
- the support/update window is sustainable;
- dependencies respect that floor;
- Windows smoke is sufficient for its stated claim;
- macOS may remain non-CI-backed for 1.0 if publicly qualified;
- toolchain upgrades can silently change generated output or behavior.

##### 13. Packaging, release, provenance, and recovery

Verify:

- tag-to-commit identity;
- deterministic package creation;
- complete archive validation;
- artifact-to-source provenance;
- local/hosted digest binding;
- immutable tags/releases;
- same-tag partial-publication recovery;
- host-side permissions/rulesets and credential scope;
- release-note correctness;
- package install/use from Haxelib/Lix-shaped layouts;
- absence of release-time tracked-source mutation.

Distinguish repository-verifiable facts from host settings requiring live empirical verification.

##### 14. Security, dependencies, and licensing

Review:

- dependency pinning and audit policy;
- workflow/action pinning and credential exposure;
- untrusted PR/fork boundaries;
- malicious metadata, paths, archives, JSON, Cargo fragments, and extra sources;
- denial-of-service inputs and compiler/runtime panic surfaces;
- fuzz/property testing opportunities at parsers and planners;
- secrets and publication identity;
- vendored Reflaxe provenance, drift, patch maintenance, and upstreaming strategy;
- licenses shipped in the package and possible implications for compiler/runtime/vendor distribution.

Do not give a legal conclusion. Identify concrete licensing questions that require qualified legal review before commercial production adoption.

##### 15. Test and evidence quality

Assess whether the test strategy finds semantic and production defects rather than merely regenerating snapshots.

Review:

- contract-first negative tests;
- runtime semantic-difference oracles;
- snapshot selection and review quality;
- determinism/repeatability assertions;
- exact generated-artifact tests;
- property, mutation, fuzz, Miri, Loom, sanitizer, or stress testing where proportionate;
- concurrency flake detection;
- platform and toolchain matrices;
- consumer-level evidence;
- current-head versus older scheduled evidence;
- release failure injection.

Do not write “add more tests.” Name the exact invariant, fixture, mutation, failure injection, or oracle needed.

##### 16. Developer and operational experience

Assess:

- installation and first compile;
- dependency and toolchain failures;
- compiler diagnostics and source positions;
- build performance;
- debugging generated Rust;
- stack traces and Haxe-to-Rust mapping;
- observability and incident diagnosis;
- upgrade/migration workflow;
- package repair and rollback;
- documentation discoverability.

A production compiler must be operable, not merely correct in CI.

##### 17. Maintainability and governance

Assess:

- architectural ownership and module boundaries;
- complexity concentration;
- bus-factor risks;
- specification/code/test synchronization;
- public inventory drift guards;
- vendored framework governance;
- release-policy governance;
- evidence freshness;
- whether Beads closure can conceal unresolved product questions.

#### Questions that require direct answers

Answer each explicitly:

1. Is reflaxe.rust suitable for any production use today? If yes, state the exact bounded workload and conditions.
2. Is it ready for 1.0 today?
3. What is the minimum coherent and useful 1.0 contract?
4. Which currently proposed surfaces should be admitted, qualified, kept experimental, or excluded?
5. Are any public claims materially misleading?
6. Are there reachable memory-safety, data-corruption, deadlock, resource-leak, or avoidable process-panic risks?
7. Is `HxRef` and the current class/object model safe and sustainable?
8. Is `hxrt` acceptably narrow, and where is compiler-known information still being deferred to runtime?
9. Does generated Rust meet a credible production quality bar for the admitted lanes?
10. Are portable and metal profile boundaries coherent?
11. Are `Dynamic`, reflection, exceptions, and fallback behavior acceptably bounded?
12. Are current std/sys/network/TLS/DB/async qualifications truthful?
13. Is the minimum-Rust/platform policy sufficient for stable admission?
14. Is the release architecture simple, correct, recoverable, and proportionate?
15. Does the compatibility manifest protect the right contracts without freezing implementation details?
16. What evidence is missing specifically for a 1.0 decision?
17. Must the scheduled weekly suite run on the exact reviewed commit before review closure, before 1.0 authorization, or only before publishing the release candidate?
18. Does the large `RustCompiler.hx` create a concrete production risk? If so, what decomposition should precede 1.0?
19. Is vendoring the current Reflaxe fork/patch set sustainable and sufficiently governed?
20. What licensing questions require professional review?
21. Which apparent gaps should explicitly remain out of scope rather than delaying 1.0?
22. Is the project suitable as a reference implementation for sibling Haxe backends? What parts are universal versus reflaxe.rust-specific?
23. Does the evidence support the Bun-class quality direction without falsely implying a BunHx commitment?
24. What are the five most consequential actions, in dependency order?

#### Required output format

##### 0. Executive disposition

Provide a table with separate verdicts and confidence for:

- bounded production use now;
- stable 1.0 compatibility promise;
- reference-implementation quality;
- progress toward the Bun-class quality north star.

Use only:

- READY
- READY_WITH_BOUNDED_SCOPE
- NOT_READY

Do not average these into one verdict.

##### 1. Exact supported-product statement

Write the exact short public statement the project could truthfully publish today.

Then write the exact stronger statement that would become defensible after your proposed 1.0 blockers are resolved.

##### 2. Stable-admission matrix

For every significant public contract family, provide:

- contract/surface;
- proposed disposition;
- exact qualification;
- protected units;
- exclusions;
- existing evidence;
- missing evidence;
- breaking-change implications.

Use the dispositions:

- Admit
- Admit-qualified
- Keep experimental
- Exclude/internalize
- Needs evidence

##### 3. Severity-ranked findings

Use a table containing:

- ID
- severity
- confidence
- repository-relative file and line evidence
- affected contract or claim
- concrete failure scenario
- root cause
- minimal root-cause fix or scope disposition
- exact regression/evidence required
- whether it blocks any production, only stable admission, or neither

Use these meanings:

- Blocker: credible memory unsafety, corruption, security compromise, unrecoverable publication identity failure, or a foundational contradiction that makes the supported product untruthful.
- High: a likely production failure, stable-contract violation, serious concurrency/resource problem, or missing evidence essential to admitting a proposed surface.
- Medium: important quality, maintainability, operability, or incomplete qualification issue.
- Low: bounded cleanup or optional hardening.

Do not inflate severity merely because a feature is incomplete.

##### 4. Cross-cutting architecture assessment

Explain:

- what architecture is sound and should be preserved;
- what is accidental complexity;
- what should be simplified;
- what should be decomposed;
- what should explicitly not be built.

Favor the smallest architecture that preserves the stated contracts.

##### 5. Empirical-verification list

Separate facts established from the bundle from assumptions requiring live or platform-specific verification.

Give exact commands, fixtures, environments, or failure injections needed. Include host settings that cannot be proven from source.

##### 6. Minimal dependency-ordered 1.0 program

Produce a dependency graph or ordered list containing only work necessary for the proposed stable contract.

For each item state:

- why it is necessary;
- whether qualification/exclusion can remove it;
- prerequisites;
- completion evidence.

Keep longer-term feature expansion out of this section.

##### 7. Concrete Beads

For each proposed issue provide:

- title;
- issue type;
- priority P0–P3;
- recommended `thinking:low|medium|high|xhigh`;
- dependencies;
- concise description;
- measurable acceptance criteria;
- relevant files;
- whether a second-pass/Oracle review is required.

Do not create duplicates for work already demonstrably complete.

##### 8. Direct answers

Answer all 24 numbered questions directly and concisely.

##### 9. Final go/no-go criteria

End with:

- present bounded-production verdict;
- present 1.0 verdict;
- exact conditions that would flip each negative verdict;
- what may remain deferred after 1.0;
- the next single action you recommend.

##### 10. Optional longer-term improvements

Keep performance expansion, additional native facades, broader parity, macOS CI, broad TLS/DB/network coverage, deeper trait/type-system work, BunHx experiments, and other non-blocking opportunities here unless evidence shows they are foundational.

#### Evidence discipline

- Cite repository-relative files and exact line ranges for findings.
- Prefer primary code, tests, workflows, and package contents over prose.
- If the bundle lacks `.git`, state that commit identity is supplied context rather than independently proven.
- Clearly label inferences.
- Do not treat a green test, a closed issue, or a documentation claim as proof by itself.
- Do not require every experimental feature to become stable.
- Do not require perfection before production use.
- Do not accept “more testing” as a recommendation without naming the exact invariant and test.
- Recommend root-cause compiler/runtime changes, not application-specific workarounds.
- Keep `codex-hxrust` independent and do not make its source architecture part of the compiler’s compatibility contract.
- Treat the supplied release as one concrete lifecycle execution, not proof of every recovery path.

## Upload checklist

### Required

#### 1. Fresh `haxe.rust` Repomix bundle from commit `a91f3cef`

Include line numbers and:

- `AGENTS.md`, `prd.md`, and `README.md`
- package, Haxelib, release, and lock manifests
- `.github/workflows/**`
- `src/**`, `runtime/**`, and `std/**`
- `vendor/reflaxe/**`
- `scripts/**`
- `docs/**`
- `examples/**` and `family/**`
- test fixtures, harnesses, snapshots, and representative expected Rust
- `.beads/issues.jsonl`
- `.beads/interactions.jsonl`

Exclude:

- `.git`
- `node_modules`
- `target`, generated build directories, caches, and `dist`
- old Repomix archives

Do **not** upload the existing `repomix-output.haxe.rust.xml.zip`; it predates the reviewed commit.

#### 2. Exact `v0.85.18` release package

Upload:

- `reflaxe.rust-0.85.18.zip`
- `reflaxe.rust-0.85.18.zip.sha256`

This lets the reviewer inspect the actual shipped compiler, runtime, vendor payload, provenance, and package layout rather than only source-tree intentions.

#### 3. Small live-evidence file

A short text or JSON file should record:

- reviewed commit
- release/tag URL
- artifact filename, byte size, and SHA-256
- current-head CI URL
- scheduled-weekly URL and its compiler commit
- consumer commit
- test/evidence counts
- Beads totals
- repository host settings verified manually

### Recommended

#### 4. Filtered `codex-hxrust` bundle at `7b590d2`

Include:

- its instructions and README
- package and HXML configuration
- `haxe_libraries/**`
- application `src/**`
- native integration sources
- test/build harnesses
- relevant scripts and docs
- compiler reference/pin metadata
- generated portable and metal `Cargo.toml`, `Cargo.lock`, `src/**`, and `hxrt/**`

Exclude all `target` directories, dependency caches, generated binaries, and unrelated history. Label it clearly as **secondary independent-consumer evidence**, not the compiler QA suite.

### Optional

#### 5. Upstream SomeRanDev/Reflaxe

Only upload a filtered upstream bundle if context permits and a serious vendor-divergence/upstreamability review is desired. The primary bundle already contains the actually shipped `vendor/reflaxe`, so upstream is useful but not required.

#### 6. Haxe 4.3.7 reference sources

A filtered bundle of the official Haxe 4.3.7 standard library and relevant typed-AST/macro definitions can help validate disputed semantic behavior. Use the exact 4.3.7 tag, not current `main`.

Do not upload `haxe.ruby`, `haxe.elixir.codex`, or an entire upstream Codex checkout for this review. They would consume context without materially helping the haxe.rust production-readiness decision.
