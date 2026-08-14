# Contained unsafe support-crate Oracle disposition

This document reconciles Oracle request
`orq_20260813T022604Z_27ed48f5` with the live haxe.rust checkout. The Oracle
response was produced by ChatGPT GPT-5.6 Pro. The local processor used
`gpt-5.6-sol` with an `xhigh` reasoning posture, as required by the request
ledger.

## Local baseline

The reviewed checkout is commit
`4ac693ba3d6b6794d4a8f91a69aac2b9170618b7`. The current compiler has two
related features, but neither owns a reproducible separate Rust crate:

- `@:rustExtraSrc` copies a Rust file into the generated application crate.
  The file therefore has the same unsafe-code policy as generated application
  code.
- Structured `@:rustCargo({path: ...})` adds a Cargo path dependency. Cargo can
  compile that separate crate, but haxe.rust does not copy, validate, hash, or
  package its source.

The focused red-state fixture proves both facts. A copied helper that contains
one `unsafe` block fails because generated `main.rs` contains
`#![forbid(unsafe_code)]`. The same helper compiles as an ambient path
dependency, but generated `Cargo.toml` points to `../support`, and no support
source is present in the generated project.

The full checkout also confirms the broader constraints in the Oracle review:

- Raw dependency text and whole-manifest replacement are still supported.
- `rust_target` is optional and is passed to Cargo only when the caller sets
  it.
- `CargoMetaRegistry` keeps process-static state and exposes rendered text,
  not an immutable typed dependency plan.
- `cargo fmt` can currently rewrite all files in a generated project.
- The repository pins Rust 1.96.0, so the Oracle's Rust version and Cargo
  resolver examples match the current toolchain policy.

## Oracle claim matrix

| Oracle recommendation | Disposition | Local decision |
| --- | --- | --- |
| Add `@:rustSupportCrate(...)` for a separate Rust library crate. | Retained | This is the missing reusable boundary. It is distinct from same-crate `@:rustExtraSrc` and ambient `@:rustCargo({path: ...})`. |
| Copy a closed source bundle, not an arbitrary Cargo project. | Retained | Version 1 admits a canonical `Cargo.toml` mirror and regular `.rs` library files below `src/`. It rejects workspaces, build scripts, binaries, nested packages, and arbitrary assets. |
| Make typed Haxe metadata the manifest authority. | Retained | haxe.rust renders the canonical manifest. A checked-in manifest must match it byte for byte so Rust developers can still use Cargo directly. |
| Force `#![forbid(unsafe_code)]` in the generated application when support crates exist. | Retained | This prevents support metadata from weakening ordinary generated or copied application code. The separate support crate receives its own closed `forbid` or `audited` policy. |
| Use an immutable per-compilation plan and read each source byte once. | Retained | The planner owns declaration, target, dependency, source, hash, and output facts. Emission uses held bytes and does not reopen the source checkout. No new process-static semantic registry is allowed. |
| Reject symlinks and special files, and replace the complete generated support subtree. | Retained | The source walk and output replacement must use no-follow operations. Stale files such as `build.rs` must not survive a later generation. This is a release blocker, not optional hardening. |
| Reject opaque Cargo authorities when a support crate is active. | Retained | Whole-manifest replacement, raw dependency defines/files, and raw-string `@:rustCargo` cannot coexist with a compiler-owned support crate. Structured application dependencies remain possible after exact name-collision checks. |
| Require an explicit `rust_target` for target-limited support. | Retained | `targets: ["*"]` is target independent. An exact target list requires one matching explicit target triple before output or Cargo execution. |
| Add a smaller typed registry-dependency grammar. | Retained with a narrow scope | Version 1 can use exact registry versions, explicit default-feature policy, and a closed feature list. Git, path, alternate-registry, optional, renamed, and target-specific dependencies remain outside the feature. This scope supports near-term low-level native crates. |
| Prefix generated support `lib.rs` with compiler-owned lint attributes. | Retained | Provenance records both source bytes and emitted bytes. The deterministic prefix enforces the selected policy without pretending that the compiler proved unsafe soundness. |
| Inspect rustc dependency inputs instead of scanning Rust text for `include!` or `#[path]`. | Retained | Text matching cannot prove the effective Rust source closure. Locked, offline build evidence must show that non-registry inputs remain below the generated support root. |
| Add a separate support-crate governance manifest. | Retained | `docs/native-facade-manifest.json` continues to govern same-crate helper files. A new package-level manifest will govern first-party support crates, their targets, dependencies, capabilities, content digest, budget, and evidence owner. |
| Never run mutating rustfmt over audited support bytes. | Retained | Support crates use `rustfmt --check`. Existing generated application formatting can keep its present behavior. |
| Do not add a public author-supplied content hash. | Retained | The compiler computes content identity. A first-party governance record can pin that digest without creating duplicate public metadata authority. |
| Use a compiler-owned workspace and one project lockfile. | Retained, subject to fixture proof | This is the smallest Cargo shape that supports workspace tests, Clippy, formatting checks, and one reviewed dependency resolution. Exact emitted TOML remains fixture-driven. |
| Use five haxe.rust delivery PRs followed by downstream adoption. | Retained as phases, not as permission to merge partial claims | Each PR must be independently useful and truthful. The reservation/documentation change comes first. Planning and emission remain unavailable until their full gates land. GameCarry adopts only a released, reviewed haxe.rust version. |
| Treat the crate boundary as proof of operating-system containment. | Rejected | It proves only Rust package and unsafe-code authority separation. GameCarry still owns descriptor-relative behavior, grants, filesystem races, platform support, and end-to-end containment tests. |
| Publish the helper crate immediately. | Deferred | A generated content-bound crate is sufficient for the first tracer. Registry publication can follow after its safe API is stable. |

## Integrated conclusion

Decision: haxe.rust will add `@:rustSupportCrate(...)`. It will not become a
general Cargo-project copier. The accepted version-1 contract is a closed Rust
library bundle that the compiler owns:

```haxe
@:rustSupportCrate({
  name: "native_page_size_support",
  sourceRoot: "native/native_page_size_support",
  unsafePolicy: "audited",
  targets: [
    "aarch64-apple-darwin",
    "x86_64-apple-darwin"
  ],
  dependencies: []
})
@:native("native_page_size_support::PageSize")
extern class PageSize {
  public static function current():rust.Result<Int, String>;
}
```

The compiler must bind this declaration to one exact source closure, target
policy, canonical manifest, content digest, generated directory, and typed
facade. The generated application remains safe Rust. Only the separate,
reviewed support crate can contain bounded unsafe code, and its safe public API
must still be reviewed and tested by its owner.

The work will proceed in these finite stages. A later source-admission review
split the old stage 2 into stages 2A and 2B:

1. Reserve and document the metadata contract with a hard unsupported-site
   diagnostic.
2. **Stage 2A:** Add the exact parser and immutable declaration request plan.
   Do not read the filesystem. Keep source admission unavailable.
3. **Stage 2B:** Add unique classpath resolution, no-follow source admission,
   canonical manifest checks, and the immutable byte plan.
4. Add exact support-subtree synchronization, workspace and path-dependency
   emission, provenance output, automatic application `forbid`, and collision
   controls.
5. Add target admission, locked/offline dependency-closure evidence, rustc
   input-closure evidence, Clippy/rustfmt checks, negative unsafe controls,
   source correlation, and compiler-server isolation.
6. Add package-install evidence, package-level governance, and one generic
   audited tracer. Then promote the metadata to `metadata-qualified`.
7. Release haxe.rust. Only then can GameCarry replace its ambient or
   handwritten native boundary with the released facility.

The [source-admission disposition](oracle-support-crate-source-admission-disposition.md)
owns this correction. It explains why Haxe 4.3.7 cannot perform the required
race-safe source read through its current public APIs.

The facility stops and requires a new design if it needs:

- arbitrary TOML or a consumer workspace.
- `build.rs`, procedural macros, or generated `OUT_DIR` source.
- path or Git dependencies for a support crate.
- nested support crates or arbitrary assets.
- Rust semantic policy inferred from source text.
- process-global semantic state.
- application-specific fields.

## Verification and unresolved gaps

Checks run against the live checkout:

- The copied-helper control failed as intended. Rust rejected the helper's
  `unsafe` block because generated `main.rs` forbids unsafe code.
- The ambient path-dependency control passed. Its generated manifest contains
  `unsafe_support = { path = "../support" }`, and the generated output does not
  own the helper source.
- The relevant compiler and policy files were inspected at exact commit
  `4ac693ba3d6b6794d4a8f91a69aac2b9170618b7`.

The Oracle did not run repository tests. Its package, dependency-graph,
source-closure, rustfmt, Clippy, compiler-server, and release-install matrices
are proposed acceptance evidence, not current results. Each implementation
stage must run its focused gates, and the final enabling stage must run the
complete local repository gate on one unchanged commit.

The following owner decisions are resolved for this implementation:

- Require the canonical checked-in Cargo mirror.
- Compute provenance in the compiler. Do not add a public hash field.
- Keep haxe.rust's first-party capability ledger separate from consumer-owned
  support-crate evidence.
- Admit only the closed exact registry-dependency grammar in version 1.
- Treat no-follow behavior on every supported compiler host as a blocker.
- Promote to `metadata-qualified` only after clean installed-package evidence.
  Defer stable status until released downstream use and a second support-crate
  shape exist.
