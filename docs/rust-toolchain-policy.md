# Rust Toolchain Policy

This is the supported compiler/toolchain contract for repository work, generated Cargo projects,
releases, and recurring evidence. The machine source is
[`rust-toolchain-policy.json`](../rust-toolchain-policy.json).

<!-- BEGIN GENERATED RUST TOOLCHAIN POLICY -->
- Minimum supported Rust: `1.96.0`
- Reproducible release toolchain: `1.96.1`
- Compatibility lane: Rust `stable`
- Generated Cargo `rust-version`: `1.96.0`
- Toolchain/floor review cadence: every 12 weeks
- Minimum notice before a floor raise: 30 days
- Earliest project release carrying a floor raise: `minor`
<!-- END GENERATED RUST TOOLCHAIN POLICY -->

## What the versions mean

- The minimum version is a real consumer floor exercised by CI. Generated default
  `Cargo.toml` files declare it through `rust-version`, so an older Cargo/rustc fails with its
  normal required-version diagnostic.
- `rust-toolchain.toml` selects the minimum version for ordinary repository work, so local default
  checks exercise the public floor rather than a newer compiler by accident.
- The release toolchain is an exact patched compiler used by artifact smoke, normal publication,
  and same-tag repair. Release workflows explicitly activate it, which makes publication
  reproducible without pretending that only one patch release can consume generated crates.
- The current-stable lane is deliberately rolling. It detects new compiler/lint incompatibilities
  early, but does not replace the minimum lane or silently raise the consumer floor. In addition to
  the workspace and a general generated smoke crate, it checks a small generated output-quality
  contract against rolling-current Clippy's `correctness` and `suspicious` groups. Those required
  groups catch semantic/lifecycle hazards without turning new style-only lints into silent compiler
  compatibility policy.
- Rust edition 2021 is a language-edition choice, not evidence for a minimum compiler version.

No Rust version older than the listed minimum is claimed. The initial floor was selected only after
the complete compiler policy suite and representative generated applications passed on that exact
compiler.

## Update and compatibility rules

- Review the release pin and floor on the generated cadence; a review does not require a change.
- Raising the minimum requires at least the generated notice period, a project minor release,
  migration/release notes, exact-minimum CI, current-stable CI, and weekly evidence on the new floor.
  It is never hidden in a patch release.
- Updating only the patched release toolchain within the same supported Rust minor line may occur in
  a project patch release after CI and release-artifact verification. It does not raise
  `rust-version`.
- Moving the release pin to a newer Rust minor without raising the supported floor requires the
  current-stable and generated-artifact lanes to pass, and ships no earlier than a project minor
  release. It also leaves generated `rust-version` unchanged.
- A security response may accelerate the release-toolchain patch, but raising the minimum still
  records an explicit compatibility disposition and uses the least disruptive safe change.
- After a stable major, this admitted update policy is the only exception to treating an arbitrary
  toolchain-floor increase as a breaking change.

## Enforcement

`npm run guard:rust-toolchain-policy` checks the structured policy, generated Haxe/TOML consumers,
Cargo manifests, pinned workflow action refs, exact minimum/current/release lane binding, the bounded
generated-current-Clippy contract, and weekly evidence. `npm run test:rust-toolchain-floor` compiles
a real generated crate, checks both app and `hxrt` manifests, rejects an older actual compiler, and
verifies Cargo supplies actionable guidance for an unmet floor.

Use `npm run toolchain:sync` only after reviewing a policy change. Generated consumers must not be
edited independently.

## First live implementation evidence

The first complete run of this policy finished on 2026-07-11 UTC:

- source/tag commit: `6499da4a15d0cfb56a21e531999cac2076dcb98c`;
- CI/release run: `29136707978`;
- exercised toolchains: minimum `1.96.0`, rolling stable `1.97.0`, and release `1.96.1`;
- immutable release/tag: `v0.85.0`, resolving to the same source commit;
- hosted artifact: `reflaxe.rust-0.85.0.zip`, 666492 bytes;
- hosted SHA-256: `27a6b2a3b5c960a5f6e945308cb6d100caed197d1ed6b7176f654b4957c60935`.

This is point-in-time evidence for one successful end-to-end execution. It does not replace the
required recurring minimum/current/weekly checks or prove every future toolchain transition.
