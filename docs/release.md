# Releases (GitHub-only)

This repository uses semantic-release for tag-derived versions and GitHub Release notes. Normal
publication does **not** modify or commit repository files.

Release policy and stable-graduation criteria live in
[SemVer And Release Posture](semver-release-posture.md). The exact current version is the latest
immutable GitHub Release tag.

## The Small Release Protocol

```text
commit S passes every required CI job
                 |
                 v
semantic-release derives version V from real tags + Conventional Commits
                 |
                 v
build and validate one deterministic Haxelib ZIP from S
                 |
                 v
create immutable tag vV at S
                 |
                 v
publish ZIP + checksum and verify hosted SHA-256
```

The tag identifies the exact commit that passed CI. There is no generated release commit, no
release-time changelog commit, and no tracked patch-version synchronization step.

## Trigger And Authority

The release job is the final job in `.github/workflows/ci.yml` and runs only for a push to `main`.
It depends on the required security, Rust, Windows, harness, performance, and stdlib jobs from the
same workflow run, checks out `${{ github.sha }}`, and alone receives `contents: write`.

The dependency audit fails on every finding except a short-lived list of exact advisory URLs under
the installed but unused `@semantic-release/npm` plugin. The project does not configure npm package
publication. The exception also requires the exact unused dependency paths, rejects critical or new
findings, and expires on 2026-09-30 so an available upstream npm fix replaces it instead of silently
turning into permanent policy.

Normal publication has no `workflow_dispatch` entry point. Manual operation is isolated in
`.github/workflows/release-repair.yml`, which accepts only an existing `vMAJOR.MINOR.PATCH` tag and
cannot derive, create, move, or delete a version tag.

## Version Policy

`release-manifest.json` contains policy only:

- major zero is `initial-development`,
- breaking commits on ungraduated `0.x` produce the next minor release,
- every stable major owns its own durable approval record,
- missing or unapproved stable majors fail closed,
- prerelease channels and build metadata are rejected until explicitly modeled.

`scripts/release/semantic-release-policy.cjs` delegates Conventional Commit parsing to the pinned
official analyzer and applies only that project policy. Exact release versions use the small
source-owned SemVer 2.0.0 syntax parser in `scripts/release/semantic-version.js`; it performs no range
selection and keeps package bytes independent of executable validation code in `node_modules`.

A repository adopting this policy without existing version tags must establish and review an
initial major-zero baseline tag (normally `v0.0.0`) before enabling automatic publication.
semantic-release otherwise treats its first release as `1.0.0`, which this manifest correctly
rejects while stable major one remains unapproved.

## Development Metadata Versus Release Metadata

Tracked metadata intentionally describes a development checkout:

- `package.json` / `package-lock.json`: `0.0.0-development`,
- `haxelib.json`: `0.0.0`,
- `haxe_libraries/reflaxe.rust.hxml`: `0.0.0-development`.

Those values never determine a release. Real tags determine the exact version. During artifact
staging, `scripts/release/prepare-package-metadata.js` writes the derived version and release note
into the copied `haxelib.json` and adds `release-metadata.json` with the version, tag, and source
commit SHA. The tracked working tree must remain unchanged.

Git installs remain pinned by tag. Packaged Haxelib installs receive the exact staged package
version. Code should treat the source-checkout HXML version as a development sentinel rather than a
published-version oracle.

## Artifact Contract

`scripts/release/package-haxelib.sh` still delegates generic Haxelib layout work to vendored
Reflaxe, then adds the target-specific `runtime/` and `vendor/` trees. It finishes with the pinned
pure-JavaScript deterministic ZIP writer rather than system `zip`.

The release adapter:

1. starts only after an externally loaded Git-object bootstrap has rechecked every tracked source byte,
2. builds the complete package twice from literal blobs in different temporary environments,
3. requires byte-identical ZIPs,
4. validates central-directory names, order, modes, compression, and path safety,
5. validates required compiler/runtime/vendor entries and staged metadata,
6. validates the shipped licenses, third-party notice, CycloneDX inventory,
   and exact vendored Reflaxe base/patch record,
7. runs the existing Haxelib install, Haxe compile, and Cargo build smoke against that exact ZIP,
8. writes its SHA-256 sidecar,
9. verifies local and remote tag identity before upload,
10. records the approved archive/checksum names, lengths, and digests in a process-local receipt that
    cannot be replaced by another mutable repository file,
11. lets the reviewed project plugin—not a general publisher—create the draft and upload only copies
    that still match that receipt,
12. verifies hosted asset names, states, sizes, and SHA-256 digests against the captured receipt after
    publication.

See `docs/release-licensing-review.md` for the factual package inventory and
the questions that still require professional legal review before 1.0.

The local paths are fixed (`dist/reflaxe.rust.zip` and `.zip.sha256`) to prevent stale globs. The
reviewed publication plugin gives them versioned hosted names. No third-party publisher receives the
mutable local artifact paths after approval.

## Changelog And Release Notes

GitHub Release notes generated from Conventional Commits are canonical beginning after `v0.81.3`.
`CHANGELOG.md` is preserved as historical material through that predecessor release; it is no
longer mutated during publication. Durable policy docs and the dynamic latest-release badge also do
not change on every patch release.

Known immutable-history note: `v0.81.4` through `v0.85.0` were published with correct tags and
artifacts but heading-only release bodies because an incompatible explicit writer preset was not
covered by an end-to-end notes assertion. Published releases remain immutable, so those bodies are
not rewritten. Their tag comparisons still expose the exact commit history. The configured notes
generator is now exercised by `npm run test:release-notes`, including feature, fix, performance,
scoped, bang-header, and breaking-footer cases. Live recovery was proven by immutable `v0.85.1`,
whose hosted body includes both release-relevant fixes from the corrected tag range.

## Partial Publication Repair

After removing the release commit, only one expected external partial state remains: a valid remote
tag exists while its GitHub Release is absent or still draft.

Run the protected **Repair Existing Release** workflow with that exact tag. Its command:

1. checks out and verifies the supplied local/remote tag identity,
2. re-derives no version and creates no tag,
3. rebuilds the deterministic package twice from the tag,
4. runs the complete exact-artifact contract and smoke,
5. captures a fresh approval receipt after smoke and checks the versioned upload copies against it,
6. creates or cleans only the associated draft Release,
7. uploads the approved ZIP/checksum, publishes the draft, and verifies immutable hosted digests
   against that receipt rather than recomputing approval from mutable local files.

If the Release is already complete and immutable, repair is a non-mutating verification. If a
published release or remote tag contains invalid content, never move/delete the remote tag or reuse
the version; treat it as an incident and issue a corrective version.

## Repository Host Controls

Future releases must use GitHub release immutability so a published tag and assets cannot change.
Version-tag rules should prevent updates/deletions and restrict creation to the release authority.
These host settings are part of the release contract, not facts that source tests can enforce by
themselves. A maintainer with repository-administration read access can audit them with
`node scripts/release/verify-host-controls.js OWNER/REPOSITORY`; the short-lived publication token
cannot read the repository-administration endpoint. Normal release and repair therefore run
`node scripts/release/verify-host-tag-controls.js OWNER/REPOSITORY` immediately before publication,
using the public ruleset API to prove that version tags cannot be updated or deleted. The
post-publication verifier separately requires the hosted Release itself to report immutable. This
split keeps both checks fail-closed within the authority GitHub actually gives each credential.

This personal repository currently enforces version-tag update/deletion protection and creates tags
with the same-run `GITHUB_TOKEN`; it does not configure a separate long-lived release credential.
An adopter with multiple writers should add a dedicated GitHub App or equivalent release identity
and a tag-creation rule that allows only that identity. Do not weaken update/deletion protection to
make normal publication convenient.

## Local Checks

Use the supported Node `22.14.x` toolchain (CI pins `22.14.0`). `rust-toolchain.toml` selects the
tested Rust minimum for ordinary repository checks; release and repair workflows explicitly
activate the exact release patch from [Rust Toolchain Policy](rust-toolchain-policy.md).
The compiler package does not ship one universal application `Cargo.lock`: generated applications
own and commit their reviewed lock, then use `-D rust_cargo_locked` for CI and release builds.
Resolver 3 guides first resolution toward the declared floor; the app lock makes that selection
reproducible.

```bash
npm run guard:release-policy
npm run test:release
npm run test:package-smoke
GITHUB_TOKEN="$(gh auth token)" npx semantic-release --dry-run
```

For reusable invariants and sibling adaptation guidance, see
[Release And SemVer Reference Architecture](release-reference-architecture.md).
