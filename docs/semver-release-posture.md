# Semver And Release Posture

Current decision date: 2026-07-09

Current scope bead: `haxe_rust-vqam`

Superseded decision: `haxe.rust-oo3.23.1` (2026-03-15)

## Current Decision

<!-- GENERATED:release-posture:start -->
Current release posture: **intentional `0.x` pre-1.0 posture**.

Maturity: **production-capable preview on validated lanes**. See [Semver And Release Posture](#current-decision).
<!-- GENERATED:release-posture:end -->

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

## Why The July 2026 Decision Stayed On 0.x

The repository has strong implementation evidence:

- broad compile/fmt/check coverage for the portable stdlib inventory,
- focused runtime semantic-diff coverage for high-risk core contracts,
- generated-Rust snapshots and strict metal/no-hxrt policy fixtures,
- package-install smoke coverage,
- Linux CI, curated Windows smoke, and a representative `codex-hxrust` pressure test.

At that review, the evidence was not yet a sufficient broad stability window for `1.0`:

- runtime semantic proof remains narrower than compile inventory coverage,
- TLS, DB, higher-level scheduler behavior, async, and Windows remain intentionally bounded by
  targeted or smoke-level evidence,
- the representative app gate still needs runtime workflow assertions beyond Cargo check/test,
- the supported Rust toolchain/MSRV policy and supported-platform promise need an explicit stable
  contract,
- and recent compiler/API change velocity has been high enough that sustained regression-free
  validation is more valuable than a major-version deadline.

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

## How Release Truth Is Generated And Verified

The structured source is `release-manifest.json`.

Why:

- prose-only release decisions can drift away from package metadata and Git tag history,
- and separately maintained copies of the same status are themselves the source of that drift.

What:

- the manifest defines each supported major line, its maturity/status language, the canonical
  document, the files that receive generated posture blocks, and the approval record required
  before stable-line generation is allowed.

How:

- `scripts/release/sync-versions.js` selects the release-line policy from the requested version,
  updates `package.json`, `package-lock.json`, `haxelib.json`,
  `haxe_libraries/reflaxe.rust.hxml`, the README badge, and every marker-delimited current-posture
  block,
- `npm run guard:release-state` renders those same outputs in memory and compares them
  byte-for-byte,
- `release.config.js` derives release-commit assets from the generator instead of repeating the
  generated-file inventory,
- semantic-release calls the same generator during `prepare`,
- a second prepare phase runs after the release commit and uses
  `scripts/release/verify-release-state.js --prepared` to verify generated state, changelog, and
  packaged haxelib/README before tag creation,
- its publish lifecycle verifies that the resulting tag contains that same release state before
  GitHub publication,
- and its success lifecycle verifies the published GitHub Release and expected zip asset.

Approving stable generation is release-sensitive `thinking:xhigh` work. It must record the Bead and
date in the manifest as part of the graduation review. The actual stable posture text is generated
only when semantic-release prepares a version on the approved stable major.

## 1.0 Graduation Gate

`1.0.0` becomes justified only when all of these conditions are recorded as passing on the intended
release candidate:

1. **Release-line correctness**
   - the release-state guard is green,
   - the semantic-release dry run derives `1.0.0` from the real Git tag lineage,
   - version metadata, changelog, tag, GitHub Release, and packaged asset are verified as one staged
     release outcome with an explicit partial-publication recovery path,
   - and the process cannot repeat the historical metadata-only `1.0.0` mistake.
2. **Current-head full evidence**
   - normal CI is green on the candidate commit,
   - a full weekly-equivalent Linux run is green on that same commit,
   - Windows smoke and `codex-hxrust` QA are green on that same commit,
   - package install/build smoke, RustSec, formatting, clippy, and release dry-run evidence are
     attached to the gate.
3. **Sustained stability window**
   - at least four consecutive weekly evidence rollups are green,
   - no unresolved release-blocking P0/P1 regression exists,
   - and a release-blocking regression restarts the window after its fix.
4. **Semantic-proof classification**
   - every surface proposed for the stable contract is classified by runtime proof depth,
   - critical snapshot/smoke-only buckets are either deepened or explicitly excluded/qualified in
     the stable support matrix,
   - and compile inventory is never presented as blanket runtime parity.
5. **Representative application runtime proof**
   - `codex-hxrust` exercises representative generated runtime workflows with assertions,
   - not only Haxe generation plus Cargo check/test-harness construction,
   - and portable/metal generated-output budgets remain within their documented contracts.
6. **Platform and Rust toolchain policy**
   - the supported operating-system matrix is explicit,
   - unsupported or smoke-only platforms are named honestly,
   - a minimum supported Rust version or equivalent pinned-toolchain policy is documented and
     enforced in CI.
7. **API and migration review**
   - public Haxe APIs, profiles, defines/metadata, generated-crate layout, runtime-facing contracts,
     and package/install workflow receive a compatibility review,
   - intentional post-1.0 change policy and deprecation/migration rules are documented,
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
