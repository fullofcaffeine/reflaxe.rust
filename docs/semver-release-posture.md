# Semver And Release Posture

Current decision date: 2026-07-13

Current scope bead: `haxe_rust-p6hs`

Superseded decision: `haxe.rust-oo3.23.1` (2026-03-15)

## Current Decision

Current release posture: **intentional `0.x` pre-1.0 posture**.

Maturity: **production-capable preview on validated lanes**.

This is durable major-line policy, not patch-version metadata. Exact versions come only from real
Git tags and immutable GitHub Releases; normal patch/minor publication does not rewrite this page.

For the July 2026 decision, that means:

- the compiler is production-capable on the validated lanes documented by the support and evidence
  pages,
- teams may use it in controlled production when their application fits those lanes and carries
  focused tests for the runtime edges it uses,
- the project is not yet making the broader compatibility and stability promise implied by a
  `1.0.0` release,
- and there is no schedule-driven reason to promote the version before the graduation evidence is
  strong enough.

This is a deliberate preview/stabilization line, not a statement that the compiler is experimental
or unusable. The distinction is about the size and maturity of the public compatibility promise.
Here, pre-1.0 means the normal `0.x` line; it does not mean a hyphenated SemVer prerelease identifier
or require GitHub's prerelease flag.

The independent 2026-07-13 production-readiness audit reaffirmed this posture: current bounded
production is `READY_WITH_BOUNDED_SCOPE`, while stable `1.0` remains `NOT_READY`. It found no
credible Rust memory-unsafety or data-corruption blocker and independently confirmed the live
release identity. It did find a smaller concrete stable-admission program: complete the public
contract at operation/signature/transitive-type level, repair or exclude admitted normal-failure,
reflection, lock/thread, and async lifecycle gaps, prove fresh dependency resolution at the Rust
floor, and assemble exact frozen-RC evidence. The verified disposition and owners are recorded in
[Production-readiness audit disposition](production-readiness-audit-2026-07-13.md).

## Why The July 2026 Decision Stayed On 0.x

The repository has strong implementation evidence:

- broad compile/fmt/check coverage for the portable stdlib inventory,
- focused runtime semantic-diff coverage for high-risk core contracts,
- generated-Rust snapshots and strict metal/no-hxrt policy fixtures,
- package-install smoke coverage,
- Linux CI, curated Windows smoke, and a representative `codex-hxrust` pressure test.

The event-based review retained `0.x` for substantive contract reasons rather than an unfinished
calendar:

- runtime semantic proof remains narrower than compile inventory coverage,
- TLS, DB, higher-level scheduler behavior, async, and Windows remain intentionally bounded by
  targeted or smoke-level evidence,
- compiler-owned portable/metal E2E workflows now have asserted generated-runtime coverage, while
  the independent app remains a compile/build consumer pressure test by design,
- the supported-platform promise remains deliberately qualified; the Rust minimum/release/current
  lanes are now governed by the explicit [Rust Toolchain Policy](rust-toolchain-policy.md),
- materially distinct baseline, defect/fix, immutable release, release no-op, exact-minimum,
  current-stable, Windows, and `codex-hxrust` events are green with no open regression bugs,
- representative-app evidence remains correctly limited to generation plus Cargo
  compile/link/test-harness construction unless that application independently adds runtime tests,
- and qualified/experimental boundaries remain intentionally broader than the exact contract the
  project is ready to admit permanently.

Weekly CI remains useful monitoring for ecosystem and runner drift. A fixed number of elapsed
Mondays is not itself a compatibility guarantee and no longer blocks posture review.

The reviewed event trail is concrete:

- CI `29136228817` exposed the GitHub-only toolchain-policy stdout bug and correctly skipped
  publication;
- commit `6499da4a15d0cfb56a21e531999cac2076dcb98c` fixed that root cause, CI/release run
  `29136707978` passed, and immutable `v0.85.0` published the same commit;
- CI `29137469525` and `29142640624` proved later bookkeeping commits produce release no-ops;
- weekly-equivalent rehearsal `29138159256` passed Linux, Windows, and `codex-hxrust` on Rust
  `1.96.0`, while required CI separately passed current stable Rust `1.97.0`;
- the open regression-bug inventory was empty at disposition.

`reflaxe.rust` is ready for continued production-capable `0.x` releases. Before calling a release
`1.0`, this repository's compiler-owned portable/metal E2E workflows must keep executing named
generated-runtime assertions, `codex-hxrust` must independently pass its normal portable/metal
consumer build at recorded SHAs, and the project must explicitly approve the exact APIs it promises
to keep compatible throughout `1.x`.

## What The 0.x Contract Promises Until Graduation

The `0.x` line promises honest evidence and migration discipline:

- `portable` and `metal` keep their documented semantic boundaries,
- supported surfaces must continue to have focused tests and clear caveats,
- intentional breaking changes require explicit migration notes and linked Beads evidence,
- published artifacts continue through GitHub Releases plus lix,
- and public wording must match the actual package/tag lineage.

While the line remains `0.x`, it does not promise that every API already has permanent `1.x`
compatibility. Teams adopting that line should pin versions and review release notes before
upgrading.

## How Release Truth Is Derived And Verified

Exact versions come from real Git tags interpreted by semantic-release. Tracked package files use
development sentinels and cannot select or obstruct that lineage.

`release-manifest.json` contains only the policy semantic-release cannot infer by itself:

- major-zero breaking changes remain on `0.x` by advancing the minor version,
- each stable major requires its own reviewed approval record,
- unknown/unapproved majors fail closed,
- release channels remain disabled until explicitly modeled.

The pinned standard `semver` package parses versions. The small policy plugin delegates commit
analysis to the official Conventional Commits analyzer and applies only the rules above.

The normal release job tags the exact commit that passed all required CI jobs. It injects the
derived version into Haxelib staging, builds the complete package twice, requires byte-identical
ZIPs, runs the real package smoke against those exact bytes, and records SHA-256. Before upload it
binds local/remote tag identity to the CI SHA; after upload it binds hosted state, size, and digest
to the approved local artifact. Published releases are immutable.

Approving a stable major is release-sensitive `thinking:xhigh` work. Add that major's Bead/date
record without removing earlier major approvals, update this durable policy page in the same review,
and prove the candidate on the intended CI commit.

## 1.0 Graduation Gate

`1.0.0` becomes justified only when all of these conditions are recorded as passing on the intended
release candidate:

1. **Release-line correctness**
   - the release-policy and focused lifecycle contracts are green,
   - the semantic-release dry run derives `1.0.0` from the real Git tag lineage,
   - the CI-tested commit, local/remote tag, staged metadata, GitHub Release, and exact packaged
     digest are verified as one identity with an explicit same-tag repair path,
   - and the process cannot repeat the historical metadata-only `1.0.0` mistake.
2. **Current-head full evidence**
   - normal CI is green on the candidate commit,
   - a full weekly-equivalent Linux run is green on that same commit,
   - Windows smoke and `codex-hxrust` QA are green on that same commit,
   - package install/build smoke, RustSec, formatting, clippy, and release dry-run evidence are
     attached to the gate.
3. **Materially distinct stability evidence**
   - evidence covers baseline validation, a real defect and root-cause fix, immutable publication,
     a later release no-op or same-tag repair, and the declared minimum/current toolchain lanes,
   - Linux local-equivalent, Windows smoke, and representative-app runs are green on explicitly
     recorded commits,
   - no unresolved release-blocking P0/P1 regression exists,
   - and any release-blocking failure requires a root-cause fix plus regression coverage before
     later evidence is relied upon.
4. **Semantic-proof classification**
   - the complete packaged public surface is classified at operation/member/signature/default and
     transitive-type level, not only by top-level type name,
   - every surface proposed for the stable contract is classified by runtime proof depth,
   - cited evidence paths and levels are mechanically validated,
   - critical snapshot/smoke-only buckets are either deepened or explicitly excluded/qualified in
     the stable support matrix,
   - and compile inventory is never presented as blanket runtime parity.
5. **Compiler runtime and independent-application proof**
   - compiler-owned portable and metal E2E workflows execute named generated-runtime assertions,
   - removal of those generated tests fails CI rather than silently passing with zero tests,
   - `codex-hxrust` independently passes its normal portable/metal build command at recorded SHAs,
   - and portable/metal generated-output budgets remain within their documented contracts.
6. **Platform and Rust toolchain policy**
   - the supported operating-system matrix is explicit,
   - unsupported or smoke-only platforms are named honestly,
   - a minimum supported Rust version or equivalent pinned-toolchain policy is documented and
     enforced in CI,
   - and representative dependency graphs resolve and build from an empty Cargo cache at that
     declared floor under the published lock/constraint policy.
7. **API and migration review**
   - public Haxe APIs, profiles, defines/metadata, generated-crate layout, runtime-facing contracts,
     and package/install workflow receive a compatibility review,
   - the review classifies stable candidates, qualified surfaces, experimental tooling, and
     excluded/internal implementation boundaries in
     [Pre-1.0 compatibility review](pre-1.0-compatibility-review.md),
   - intentional post-1.0 change policy and deprecation/migration rules are documented,
   - every admitted normal OS/runtime failure is Haxe-visible rather than a raw Rust panic,
   - accepted reflection paths contain no sentinel or reachable `todo!()` behavior,
   - admitted lock/thread/async surfaces have explicit reentry, unwind, cancellation, and cleanup
     contracts, while unproved breadth remains experimental,
   - and known defers remain visible rather than being hidden by the version bump.
8. **Independent second pass**
   - the final go/no-go receives the repository's required `thinking:xhigh` review,
   - findings and disposition are recorded in Beads,
   - and the release is a no-go if evidence and public scope do not agree.

These criteria are intentionally measurable. They do not require blanket Haxe parity, every
platform, or every Rust-native API. They require the stable claim to match the exact surface and
evidence the project is prepared to maintain.

## Packaging Posture

The distribution channel does not need to change before `1.0`:

- release artifacts are published through GitHub Releases,
- install flow is GitHub plus lix,
- the packaged zip remains haxelib-shaped because that is the correct install artifact,
- haxelib.org publication is a separate decision.

## Superseded March 2026 Decision

Milestone 29 (`haxe.rust-oo3.23`) chose a `1.0` direction and updated versioned metadata to `1.0.0`.
That decision is preserved in Beads and the historical GA documents.

It did not create a `v1.0.0` Git tag or GitHub Release. The next semantic-release run correctly
derived its version from the latest real tag (`v0.62.0`), published `v0.62.1`, and synchronized the
metadata back to the actual `0.x` line. Later releases continued through that lineage.

The mismatch showed that editing version files was not an executed release decision. The current
intentional pre-1.0 decision supersedes that unexecuted posture while preserving its reasoning as
historical context. Future `1.0` work must satisfy the graduation gate above rather than merely
repeating the metadata change.
