# Releases (GitHub-only)

This repo uses **semantic-release** to publish GitHub Releases and keep versions/changelog in sync.

## Trigger

- Releases run on `main` after the `CI` workflow completes successfully (`.github/workflows/release.yml`).
- The release job skips when the triggering commit is already a release commit (`chore(release): ...`).

## Versioning + changelog

- Version bumps follow **Conventional Commits** (e.g. `feat: ...`, `fix: ...`).
- `semantic-release` updates:
  - `CHANGELOG.md`
  - `package.json` / `package-lock.json`
  - `haxelib.json`
  - `haxe_libraries/reflaxe.rust.hxml`
  - `README.md` (version badge)

Those updates are committed back to `main` as `chore(release): <version>`.

## Release assets

- The workflow builds a zip at `dist/reflaxe.rust-<version>.zip` via:
  - `scripts/release/sync-versions.js`
  - `scripts/release/package-haxelib.sh`
- The zip is uploaded to the GitHub Release as an asset.
- Packaging semantics intentionally mirror Reflaxe `build` behavior:
  - copy `classPath` into the package root
  - merge `reflaxe.stdPaths` into `classPath`
  - include `LICENSE` + `README.md`
  - sanitize `haxelib.json` by removing the `reflaxe` metadata block
- Target-specific additions (required by this backend):
  - bundled runtime sources under `runtime/`
  - vendored Reflaxe framework sources under `vendor/`
- CI guard: `scripts/ci/package-smoke.sh` validates the built zip by installing it into an isolated
  local haxelib repo and compiling/building a smoke app via `-lib reflaxe.rust`.

Note: even though we package a “haxelib style” zip, the intended distribution path for now is GitHub
releases + lix (not publishing to haxelib).

## Auth

- If `RELEASE_TOKEN` is configured as a GitHub Actions secret, it is used.
- Otherwise the workflow falls back to `github.token`.

## Local dry run

To see what semantic-release *would* do (without pushing), you can run:

`npx semantic-release --dry-run`
