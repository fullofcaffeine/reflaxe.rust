# Typed Rust support-crate facility

Status: design reserved. `@:rustSupportCrate` is not available for application
use. The compiler rejects it until the complete contract has implementation and
evidence.

## Why this facility exists

Generated application code can forbid all unsafe Rust:

```rust
#![forbid(unsafe_code)]
```

This rule also applies to files copied into the application with
`@:rustExtraSrc`. Therefore, a copied file cannot contain even one reviewed
`unsafe` block.

Cargo can compile a separate crate with a different unsafe-code policy. The
current `@:rustCargo({path: ...})` metadata can link such a crate. However, the
path is ambient input. haxe.rust does not copy, validate, hash, or package that
source.

The planned `@:rustSupportCrate` facility closes this gap. It will let one
typed Haxe facade select one closed Rust library bundle. haxe.rust will own the
bundle's exact source bytes, generated location, Cargo connection, and content
identity.

This boundary does not prove that an unsafe operation is sound. The support
crate owner must still review its safety rules and test its public API.

## Intended Haxe surface

The metadata has exactly one object argument:

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

All five fields are required:

- `name` is one lowercase Rust crate identifier. It is also the Cargo package,
  dependency, import, and generated-directory name.
- `sourceRoot` is one classpath-relative source directory. It cannot be an
  absolute path or contain empty, current-directory, or parent-directory
  segments. It must resolve through exactly one active Haxe class path. The
  compiler rejects missing or duplicate matches.
- `unsafePolicy` is `"forbid"` or `"audited"`. `"audited"` grants a separate
  crate permission to contain reviewed unsafe code. It is not a soundness
  certificate.
- `targets` is either exactly `["*"]` or a unique list of exact Cargo target
  triples. A target-specific crate requires a matching `rust_target` define.
- `dependencies` is an explicit list, including `[]` when the crate has no
  direct dependency.

A direct dependency uses this closed form:

```haxe
{
  name: "libc",
  version: "=0.2.180",
  defaultFeatures: false,
  features: []
}
```

Version 1 accepts only exact default-registry versions. It rejects version
ranges, Git, paths, alternate registries, renamed packages, optional
dependencies, target-specific dependency sections, and raw Cargo text.

The metadata can appear only on an `extern class`. Its structural `@:native`
path must start with the same crate name. For example,
`native_page_size_support::PageSize` matches `name:
"native_page_size_support"`.

Several externs can repeat one identical declaration. The compiler will merge
only declarations that are exactly equal after normalization. It will not
combine different targets, dependencies, features, or unsafe policies.

## Closed source bundle

The source root is a Rust library bundle, not an arbitrary Cargo project:

```text
native/native_page_size_support/
├── Cargo.toml
└── src/
    ├── lib.rs
    ├── page_size.rs
    └── platform/
        └── mod.rs
```

The bundle admits:

- one required `Cargo.toml`.
- one required `src/lib.rs`.
- regular UTF-8 `.rs` files below `src/`.
- lowercase Rust identifier path segments.

The bundle rejects:

- symlinks and special files.
- `build.rs` and `Cargo.lock`.
- `.cargo`, nested manifests, and nested workspaces.
- binary, integration-test, example, and benchmark targets.
- non-Rust assets.
- hidden files and case-folded path collisions.
- byte-order marks, NUL bytes, invalid UTF-8, and non-canonical line endings.

The compiler must inspect file kinds without following links. Resolving a
symlink and checking the final path is not sufficient.

Typed Haxe metadata owns the Cargo manifest. haxe.rust will render the only
accepted `Cargo.toml` bytes. The checked-in manifest must match those bytes
exactly. This mirror keeps normal Cargo development possible without admitting
arbitrary manifest behavior.

The compiler will read every admitted source byte once. One immutable plan will
hold the copied bytes, lengths, hashes, owners, target policy, dependency
policy, and generated destination. Output code will use that plan and will not
reopen the source checkout.

## Generated project

The planned output has one application crate and one sibling directory for
support crates:

```text
out/
├── Cargo.toml
├── Cargo.lock
├── src/
│   └── main.rs
└── support-crates/
    ├── plan.json
    └── native_page_size_support/
        ├── Cargo.toml
        └── src/
            ├── lib.rs
            └── page_size.rs
```

The application crate will receive `#![forbid(unsafe_code)]` automatically.
The caller will not need to remember `-D rust_forbid_unsafe`.

The support crate will receive compiler-owned lint attributes for its selected
policy. An audited crate can contain bounded unsafe code. A forbidden crate
cannot.

The root Cargo manifest will use a deterministic relative path dependency and
one workspace lockfile. The compiler will own the complete
`support-crates/` subtree. It must remove stale compiler-owned files before
Cargo runs and must not follow links during replacement.

`support-crates/plan.json` will record relative paths, file sizes, SHA-256
hashes, content identity, target, and owning Haxe metadata. It will never
contain a machine-local checkout path.

Copied Rust source does not receive a false Haxe source map. The plan provides
source correlation from a Rust diagnostic to the owning Haxe declaration.

## Cargo compatibility rule

Opaque Cargo input cannot coexist with a compiler-owned support crate. When a
support crate is present, the compiler will reject:

- `rust_cargo_toml`.
- `rust_cargo_deps`.
- `rust_cargo_deps_file`.
- raw-string `@:rustCargo(...)`.

Structured `@:rustCargo({...})` remains possible after exact dependency-name
collision checks. Compilations without support crates keep their current Cargo
behavior.

The resolved dependency check will inspect only packages reachable from the
support crate. Custom-build targets, procedural macros, and native-link
packages fail unless a separate reviewed capability record admits the exact
package and version.

Mandatory verification uses a reviewed lockfile with `--locked --offline`.
It also inspects rustc dependency information. This proves that non-registry
source inputs remain below the generated support root without unreliable Rust
source-text matching.

## Ownership

The responsibilities remain separate:

- haxe.rust owns metadata parsing, source admission, deterministic planning,
  Cargo generation, target checks, generated replacement, hashes,
  diagnostics, package contents, and compiler-server isolation.
- The Haxe facade owner owns exact signatures and Rust path bindings. The
  facade cannot use `Dynamic`, `Any`, unchecked casts, or raw target bodies.
- The support-crate owner owns every unsafe block, its documented safety
  conditions, cleanup, thread behavior, and safe public Rust contract.
- The project lockfile owns exact registry versions and resolved Cargo
  capabilities.
- A new support-crate governance manifest will own first-party source budgets,
  content pins, allowed dependencies, forbidden growth, and evidence links.
- A downstream product owns its protocol, paths, permissions, platform
  support, and end-to-end security claims.

A successful Cargo build proves that generated application code can call the
safe support API without an unsafe block. It does not prove operating-system
containment or the semantic soundness of the support implementation.

## Delivery stages

The feature has finite delivery stages:

1. Reserve and document the public metadata. Reject every typed declaration or
   field use. Haxe discards ordinary expression metadata that has no typed
   meaning, so expression metadata cannot request this facility and is not part
   of its placement grammar.
2. Add the exact parser and immutable plans. Keep emission disabled.
3. Add exact artifact and Cargo emission behind the planned contract.
4. Add target, dependency, unsafe, tool, and compiler-server proof.
5. Add installed-package proof, package governance, and one generic tracer.
6. Release haxe.rust before a downstream product adopts the facility.

The metadata becomes `metadata-qualified` only after stage 5. Stable status
requires one released downstream consumer and a second distinct support-crate
shape.

## Stop criteria

Stop and design another facility if implementation requires:

- arbitrary Cargo TOML or a consumer-supplied workspace.
- `build.rs`, procedural macros, or generated `OUT_DIR` source.
- Git, path, or alternate-registry support dependencies.
- support crates that depend on other support crates.
- binaries, examples, benchmarks, integration tests, or arbitrary assets.
- Rust method bodies stored in Haxe strings.
- Rust semantic policy inferred from text matching.
- process-global planning state.
- automatic rewriting of audited support source.
- product-specific fields or compiler recognition.

Use a separately published crate or another reviewed contract when a real need
crosses one of these limits.

## Current evidence

`test/contract/contained_unsafe_boundary_red_state` records the missing
boundary:

- copied unsafe source fails under the generated application's
  `forbid(unsafe_code)` rule.
- an ambient support path compiles but is absent from generated ownership and
  package output.

The negative fixtures prove that application code cannot silently opt into the
unfinished facility. They cover metadata on a type and on a field.

The reconciled independent architecture review and local decision matrix are
in [the Oracle disposition](oracle-contained-unsafe-support-crate-disposition.md).
