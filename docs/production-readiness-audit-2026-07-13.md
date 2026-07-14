# Production-readiness audit disposition — 2026-07-13

This page records the repository disposition of the independent GPT-5.6 Pro review of commit
`a91f3cefca9d33cf9668cdceb9267a164b688868` and immutable release `v0.85.18`.

It is a review and work-ownership record, not a stable-major authorization. The owning follow-up is
Bead epic `haxe_rust-p6hs`.

## Executive result

| Question | Disposition | Meaning |
| --- | --- | --- |
| Bounded production use now | `READY_WITH_BOUNDED_SCOPE` | Pinned, tested applications may use the documented portable subset and narrow typed metal islands. Application-specific runtime edges still require application tests. |
| Stable `1.x` compatibility promise | `NOT_READY` | The package-complete source graph now exists, but the exact admitted set is not authorized and several candidate surfaces still have failure or lifecycle gaps. |
| Reference implementation | `READY_WITH_BOUNDED_SCOPE` | The profile model, AST-first direction, semantic-difference tests, generated contracts, no-hxrt enforcement, and release design are reusable patterns. The compiler monolith and raw-AST blind spots are not patterns to copy blindly. |
| Bun-class workload quality direction | `READY_WITH_BOUNDED_SCOPE` | The direction is credible, but current evidence does not establish workload-scale latency, allocation, cancellation, debugging, or operational quality. This remains a quality bar, not a BunHx commitment. |

No credible Rust memory-unsafety, undefined-behavior, or data-corruption blocker was established.
The important confirmed risks are availability, failure conversion, lifecycle cleanup, resource
retention, and public-contract completeness.

## Plain-language interpretation

The compiler is already useful for real production work when the application stays inside a known,
tested lane and pins its compiler/toolchain/dependencies. The audit did **not** conclude that the
compiler is broadly unsafe or that its release design should be rewritten.

The missing step for `1.0` is more precise:

1. mechanically define the exact operations and signatures promised throughout `1.x`;
2. fix the normal-failure and lifecycle defects inside that chosen set, or keep those operations
   experimental/qualified;
3. prove fresh toolchain/dependency resolution and the exact frozen release candidate;
4. make a separate reviewed major-1 authorization decision.

This deliberately does not require universal Haxe/std/sys parity, macOS CI, a tracing garbage
collector, broad TLS/DB/network/async expansion, or BunHx.

## Verified findings

The repository verified the audit against the reviewed tree before creating follow-up work.

### Confirmed implementation and contract gaps

| Area | Verified state | Owner |
| --- | --- | --- |
| Public compatibility authority | Schema v2 inventories 318 shipped/importable Haxe declarations and 1,541 public operations across the installed class-path sources. It protects normalized signatures, constructors, defaults, generic bounds, direct/transitive shipped types, metadata/define grammar, lifecycle state, and validated evidence IDs. The compiler-owned boundary now seals every internal helper root while preserving the explicitly classified public injection shim; admitted APIs cannot close over candidate, experimental, or internal transitive types. Candidate status remains distinct from stable admission. | `.2` and `.3` complete |
| Portable `Sys` and standard I/O failure behavior | Admitted core path/process failures now cross a catchable Haxe string boundary, standard-stream failures use typed `haxe.io.Error`, and stdin EOF remains distinct from read errors. `Sys.cpuTime()` throws explicitly and remains experimental until a real process CPU clock is implemented; non-Windows concurrent `Sys.putEnv` remains experimental rather than receiving a false safety promise. | `haxe_rust-p6hs.4` complete |
| Reflection and call stacks | The selected closed-world `Type.*` name/resolve/constructor-list operations now use a deterministic compiler-generated registry with Haxe-oracle semantics and no `todo!()` or sentinel output. Dynamic construction is excluded: direct application calls receive `HXRS-REFLECTION-UNSUPPORTED`, while retained upstream `haxe.Unserializer` branches throw a Haxe-catchable operation-specific error. `CallStack` names/signatures are a qualified API-shape candidate; current empty contents, native frames, source mapping, and exact formatting are explicitly not admitted. The targeted contract, complete repository harness, package smoke, and independent application pressure test are green. | `haxe_rust-p6hs.5` complete |
| `HxRef` lifecycle | The safe representation remains opaque. Executable evidence now protects shared identity, alias-visible mutation, final-owner cleanup for acyclic values, deliberate strong-cycle retention and explicit break behavior, plus stable Send/Sync diagnostic identifiers at known thread crossings. Strong cycles remain outside tracing-GC guarantees; no collector or new runtime surface was added. | `haxe_rust-p6hs.6` complete |
| Native lock callbacks | Same-handle mutex/RwLock callback reentry now throws the catchable `HXRT-LOCK-REENTRANCY` error before acquisition, including read/write upgrade shapes. The real guard remains held, different-handle nesting remains valid, and RAII clears the callback marker after normal return or unwind. | `haxe_rust-p6hs.7` complete |
| Threads and EventLoop | Spawned jobs now own registry cleanup through RAII across normal return, Haxe throw, and Rust unwind. Detached uncaught Haxe errors terminate only the child; dead sends fail catchably. Repeats advance before callbacks, cancellation can suppress later due work, and unmatched promised delivery is rejected before enqueue. The isolated subprocess contract covers cleanup stress, callback throws, cancellation, and promise balance with hard timeouts. | `haxe_rust-p6hs.8` |
| Async lifecycle | The current preview bridge does not yet own a complete cancellation, join/drop, panic, shutdown, nested-runtime, and adapter-scoping contract. It may remain experimental instead of blocking narrow `1.0`. | `haxe_rust-p6hs.9` |
| Structured Cargo metadata | `@:rustCargo` does not yet reject extra arguments or unknown object fields as a closed stable grammar. | `haxe_rust-p6hs.10` |
| Rust floor and dependency resolution | Exact-minimum CI proves the checked graph and generated `rust-version`, but not future empty-cache resolution across the representative feature graph. | `haxe_rust-p6hs.11` |
| CI supply-chain inputs | Material action/tool identities are not all commit/digest pinned. | `haxe_rust-p6hs.12` |
| Vendored framework governance and licenses | The shipped vendor tree exists, but its patch/provenance prose is stale and still carries Elixir-origin/workaround-era rationale. Exact upstream-base drift, notices/SBOM, and professional legal questions need explicit closure. | `haxe_rust-p6hs.13` |

### Confirmed qualifications, not mandatory feature work

- `HxRef` strong cycles may remain uncollected if the stable contract and production guidance state
  that limit and supply explicit cleanup evidence. A tracing GC is not a `1.0` requirement.
- Broad runtime reflection remains experimental. Unsupported application-authored dynamic
  construction is a stable compile-time error, while unavoidable upstream generic branches remain
  compilable and fail catchably when reached; neither path emits sentinels or `todo!()` output.
- `rust_async`, broader EventLoop/MainLoop/pool semantics, UDP, TLS, MySQL runtime, broad SQLite/network behavior,
  raw Rust, and custom Cargo ownership may remain experimental or narrowly qualified.
- Empty `CallStack` contents may remain outside the stable promise if the API/content distinction is
  explicit. Full source mapping is an operability improvement, not automatically a narrow-`1.0`
  blocker.
- The approximately 18,000-line `RustCompiler.hx` is a change-risk concentration, but a cosmetic
  rewrite is not a release gate. Extract only dependency-oriented seams required by confirmed work,
  with byte-for-byte characterization around unaffected output.

## Audit-package omissions versus repository defects

The external review correctly marked several facts as unverified because the uploaded bundle omitted
requested files. Local and hosted verification found:

- `package-lock.json`, `LICENSE`, and `vendor/reflaxe/**` are tracked in the repository;
- `test/semantic_diff/sys_thread_event_loop` exists in the reviewed tree;
- the hosted `reflaxe.rust-0.85.18.zip` is 688,087 bytes;
- its SHA-256 is
  `42df24e23dd808f52f8f2e3e7b26c8667e5e26c4f6b73e8a86438de52319e34d`;
- the downloaded sidecar verifies that digest;
- `scripts/release/verify-release-artifact.js` accepts the exact hosted ZIP for version `0.85.18`,
  tag `v0.85.18`, and source commit `a91f3cefca9d33cf9668cdceb9267a164b688868`;
- the package contains the required compiler, runtime, standard-library, vendor, license, and release
  metadata roots;
- GitHub reports the hosted asset digest and immutable release state consistently.

Therefore the audit's missing-artifact finding is closed as an **audit-package evidence omission**,
not a defect in the current release architecture or hosted artifact. Vendor governance and license
disposition remain separate real work.

One cited evidence path, `test/upstream-stdlib-api-manifest.json`, genuinely did not exist. Schema v2
removed that stale broad-family reference, replaced it with operation-level source ownership, and
now rejects missing file, npm-script, or Bead evidence targets.

## Bounded production contract today

Current production use remains appropriate when all of the following are true:

- the application pins Haxe `4.3.7`, an immutable compiler release/commit, Rust/Cargo policy, and
  Cargo lockfiles;
- used language/std operations are inside the documented evidence-backed set;
- every used file, process, network, TLS, DB, thread, or async edge has application-specific tests;
- the application does not rely on dynamic class/enum construction, unlisted `Type.*` reflection,
  useful native call stacks, successful same-handle native lock callback reentry (it is
  deterministically rejected), broader scheduler parity, or unproven async cancellation/shutdown;
- admitted core `Sys` and standard-stream failures are Haxe-catchable, while every additional file,
  process, network, TLS, DB, thread, or async failure path used by the application still has its own
  runtime evidence;
- long-lived strong object cycles are avoided or explicitly broken;
- Linux is the full-validation lane, Windows use is limited to named smoke coverage, and macOS is
  treated as local contributor validation only.

This is controlled production, not arbitrary drop-in Haxe target parity.

## Dependency-ordered stable-major path

The active Beads graph is:

1. `haxe_rust-p6hs.2` — package-complete operation/member/signature/transitive compatibility graph
   (foundation implemented).
2. `haxe_rust-p6hs.3` — package-wide public/internal boundary closure (foundation implemented).
3. `haxe_rust-p6hs.4` — portable core `Sys`/standard-stream failure behavior (implemented); `.5` —
   closed-world reflection and CallStack qualification (implemented); `.6` through `.8` — HxRef,
   native-lock, and thread/EventLoop lifecycle contracts (implemented); `.9` and `.10` — next:
   explicitly scope async and close the selected structured-metadata surface.
4. `haxe_rust-p6hs.11` through `.13` — fresh MSRV resolution, CI input identity, vendor/license
   governance.
5. `haxe_rust-p6hs.14` — exact frozen-RC evidence plus independent major-1 GO/NO-GO.

The graph is intentionally smaller than the audit's optional improvement list. Optional performance,
platform, facade, type-system, and Bun-class workload expansion stays outside the stable-major
critical path unless new evidence changes the selected contract.

## Second-pass disposition

This integration uses the supplied GPT-5.6 Pro audit as the required independent second pass for
the `thinking:xhigh` scope decision. The review's overall disposition is accepted with these local
corrections:

- accept `READY_WITH_BOUNDED_SCOPE` for current production and `NOT_READY` for stable `1.0`;
- accept the confirmed failure, reflection, lifecycle, contract, MSRV, supply-chain, and vendor
  findings as owned follow-up;
- resolve broad feature gaps through explicit qualification/exclusion when they are outside the
  selected stable set;
- do not treat omitted upload contents as missing repository or release contents;
- preserve the simplified tested-commit → deterministic artifact → same-commit tag → immutable
  hosted release architecture.
