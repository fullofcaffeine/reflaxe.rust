# Releases (GitHub-only)

This repo uses **semantic-release** to publish GitHub Releases and keep versions/changelog in sync.

## Current Public Posture

<!-- GENERATED:release-posture:start -->
Current release posture: **intentional `0.x` pre-1.0 posture**.

Maturity: **production-capable preview on validated lanes**. See [Semver And Release Posture](semver-release-posture.md).
<!-- GENERATED:release-posture:end -->

- public distribution path: GitHub Releases plus lix
- packaged artifact format: haxelib-shaped zip
- scope authority: the generated posture block and canonical decision page above
- not implied by this repo: haxelib.org publication or compatibility beyond that documented scope

The canonical decision and measurable graduation criteria live in
[Semver And Release Posture](semver-release-posture.md).

## Trigger

- Releases run on `main` after the `CI` workflow completes successfully (`.github/workflows/release.yml`).
- The release job skips when the triggering commit is already a release commit (`chore(release): ...`).

## Versioning And Changelog

- Version bumps follow **Conventional Commits** (for example `feat: ...` and `fix: ...`).
- Every line continues from real Git tags produced by semantic-release.
- Editing package metadata alone does not establish a release line; any graduation must derive its
  version from the real tag lineage and complete the tag/release/asset flow.
- `semantic-release` updates:
  - `CHANGELOG.md`
  - `package.json` / `package-lock.json`
  - `haxelib.json`
  - `haxe_libraries/reflaxe.rust.hxml`
  - `README.md` (version badge)

Those updates are committed back to `main` as `chore(release): <version>`.

## Structured Release State

Run:

`npm run guard:release-state`

`release-manifest.json` is the structured policy source. `scripts/release/sync-versions.js` derives
the active release line from the version and generates all version surfaces plus marker-delimited
current-status prose. `--check` renders the same outputs without writing and compares them
byte-for-byte. `release.config.js` obtains the release-commit asset list from that generator, so the
workflow does not repeat the manifest's generated-file inventory.

The release workflow invokes that generator during semantic-release `prepare`. A second exec phase
runs after the release commit and verifies generated state, changelog, and packaged haxelib/README
before semantic-release creates the tag. The publish phase verifies that the resulting tag contains
the same release state before GitHub publication. The success lifecycle then verifies the published
GitHub Release and expected zip asset. Stable-line generation remains disabled in the manifest until
a reviewed graduation record enables it.

This generator is the ownership boundary, not a temporary phrase scanner. It should be replaced
only if the release system itself becomes the structured source and can generate and verify the same
metadata, docs, tag, changelog, and artifact contract with equivalent regression coverage.

For the reusable invariants and sibling-repository adoption sequence, see
[Release And SemVer Reference Architecture](release-reference-architecture.md).

## Release Assets

- The workflow builds a zip at `dist/reflaxe.rust-<version>.zip` via:
  - `scripts/release/sync-versions.js`
  - `scripts/release/package-haxelib.sh`
- The zip is uploaded to the GitHub Release as an asset.
- Packaging semantics intentionally mirror Reflaxe `build` behavior:
  - copy `classPath` into the package root
  - merge `reflaxe.stdPaths` into `classPath`
  - convert files from `_std` std paths into packaged `.cross.hx` files
  - include `LICENSE` + `README.md`
  - sanitize `haxelib.json` by removing the `reflaxe` metadata block
- Target-specific additions required by this backend:
  - bundled runtime sources under `runtime/`
  - vendored Reflaxe framework sources under `vendor/`
- CI guard: `scripts/ci/package-smoke.sh` validates the built zip by installing it into an isolated
  local haxelib repo and compiling/building a smoke app via `-lib reflaxe.rust`.

The haxelib-shaped zip is the install artifact. The intended distribution path remains GitHub
Releases plus lix.

## Partial Publication Recovery

The prepared-commit verifier prevents deterministic metadata/docs/artifact failures from creating a
tag. Git and GitHub still cannot form one external transaction: a network or GitHub failure can
happen after the tag is pushed but before the Release or asset is complete.

Treat that state as a failed release of the same version, not permission to advance the version:

1. open a release-sensitive Bead and preserve the failed-run evidence,
2. rebuild the exact artifact from the tagged commit,
3. run `scripts/release/verify-release-state.js <version>` against the tag and artifact,
4. repair or create the GitHub Release/asset for that same tag,
5. run `scripts/release/verify-release-state.js <version> --published`,
6. delete or replace an unpublished tag only under explicit `thinking:xhigh` review when the tagged
   content itself is invalid and cannot be repaired safely.

## Release Toolchain

The release job installs the same pinned lix Haxe toolchain used by CI before running
`semantic-release`. This is required because semantic-release runs `scripts/release/package-haxelib.sh`
from `prepareCmd`, and that packaging script invokes Reflaxe build through `haxe`.

Keep `.github/workflows/release.yml` aligned with the CI package-smoke Haxe setup. `npm ci
--ignore-scripts` intentionally skips the lix postinstall hook; without explicit `npx lix download`
and `npx lix use haxe 4.3.7` steps, release packaging can fail when `haxelib` cannot find its Neko
runtime.

## Auth

- If `RELEASE_TOKEN` is configured as a GitHub Actions secret, it is used.
- Otherwise the workflow falls back to `github.token`.

## Local Dry Run

To see what semantic-release would do without pushing:

`npx semantic-release --dry-run`
