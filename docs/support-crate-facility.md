# Typed Rust support-crate facility

Status: source admission is implemented for Apple Silicon macOS. The compiler
reads an exact support-crate bundle, validates it, and stops with
`HXRS-SUPPORT-CRATE-EMISSION-DISABLED`.

The compiler does not add the admitted crate to generated Cargo output yet.
Linux and Windows stop before source admission. No pathname fallback is used.

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

The `@:rustSupportCrate` facility closes this gap in finite stages. It lets one
typed Haxe facade select one closed Rust library bundle. haxe.rust owns the
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

- `name` is one lowercase Rust crate identifier of at most 64 characters. It is also the Cargo package,
  dependency, import, and generated-directory name. Rust keywords and the
  backend-reserved crate roots `std`, `core`, and `alloc`, and Cargo's reserved
  package name `test` are not valid names.
- `sourceRoot` is one classpath-relative source directory. It cannot be an
  absolute path or contain empty, current-directory, or parent-directory
  segments. It must resolve through exactly one active Haxe class path. The
  compiler rejects missing or duplicate matches.
- `unsafePolicy` is `"forbid"` or `"audited"`. `"audited"` grants a separate
  crate permission to contain reviewed unsafe code. It is not a soundness
  certificate.
- `targets` is either exactly `["*"]` or a unique list of exact Cargo target
  names, including targets such as `thumbv8m.main-none-eabi` that contain a
  dotted architecture segment. A target-specific crate requires a matching
  `rust_target` define.
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

Version 1 accepts only canonical, stable `=major.minor.patch` versions from the
default registry. It rejects prerelease/build suffixes, leading-zero versions,
SemVer components larger than Cargo's unsigned 64-bit limit, version ranges,
Git, paths, alternate registries, renamed packages, optional
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

The helper reads every candidate source byte in two complete passes. It compares
the two trees to detect a change during admission. Only the validated first copy
crosses the protocol boundary. The compiler validates that copy and stores it in
one immutable plan. Later output code will use the plan and will not reopen the
source checkout.

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

The feature has finite delivery stages. Stages 1, 2A, and 2B are implemented:

1. Reserve and document the public metadata. Reject every typed declaration or
   field use. Haxe discards ordinary expression metadata that has no typed
   meaning, so expression metadata cannot request this facility and is not part
   of its placement grammar.
2. **Stage 2A:** Parse the exact declaration into an immutable request plan.
   Do not read the filesystem. Stop with the source-admission diagnostic.
3. **Stage 2B:** Admit exact source bytes with one package-owned native helper.
   Stop with an emission-disabled diagnostic.
4. Add exact artifact and Cargo emission behind the admitted source plan.
5. Add target, dependency, unsafe, tool, and compiler-server proof.
6. Add installed-package proof, package governance, and one generic tracer.
7. Release haxe.rust before a downstream product adopts the facility.

### What Stage 2A does

The compiler accepts the exact five-field object on an `extern class`. It
checks the crate name, logical source root, unsafe policy, targets, registry
dependencies, and matching `@:native` prefix.

The compiler normalizes target, dependency, and feature order. Therefore, two
declarations can use a different source order and still describe one request.
Every other value must be equal. The compiler rejects union-style merging.

Haxe can remove metadata from expression types after typing is complete. The
planner therefore runs in the final typing callback. It stores only normalized
request facts or one diagnostic. The later compile step clears those detached
records before it reports an error. This order keeps warm compiler requests
separate and does not retain a mutable typed program as proof.

For example, this declaration has valid syntax:

```haxe
@:rustSupportCrate({
  name: "native_page_size_support",
  sourceRoot: "native/native_page_size_support",
  unsafePolicy: "audited",
  targets: ["*"],
  dependencies: []
})
@:native("native_page_size_support::PageSize")
extern class PageSize {}
```

The compiler then reports:

```text
[HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE]
```

This result means that the declaration is valid. It does not mean that the
source directory exists or contains reviewed bytes.

### What Stage 2B does

Haxe 4.3.7 can inspect and read files by pathname. It cannot open one child
relative to an already open parent directory through its macro API.

Another process can replace a pathname component between a kind check and a
later read. The package-owned helper opens each child relative to an open
parent directory. An open directory is called a pinned directory here. A later
pathname replacement cannot redirect reads below that pinned directory.

The helper opens each selected child once, relative to the pinned parent. It
keeps that exact child descriptor for the later directory walk or file read.
It does not reopen the child name after a separate identity check.

This rule avoids an inode-reuse gap. Some filesystems can reuse an inode number
after a replacement. A pathname plus that number is therefore not permanent
authority for a later read. The retained descriptor continues to refer to the
object that the helper opened. The second complete traversal rejects a changed
namespace or changed bytes.

The helper logic is Haxe source compiled through the haxe.rust Metal profile.
A small safe-Rust facade calls the operating-system directory APIs. The facade
contains no `unsafe` block. It does not contain product rules or manifest
policy.

The compiler starts the packaged helper directly. It does not use a
shell, `PATH`, a download, or a consumer-side build. The compiler checks the
helper size, execute mode, and SHA-256 digest before it starts the process.

This is a verify-then-execute boundary on macOS. It does not prove that the
executed inode is the same inode that was hashed. The installed haxe.rust package
directory is therefore a trusted boundary. A process that can replace files in
that directory can also replace compiler code. A future platform facade can add
a stronger execute-by-descriptor operation without changing the protocol.

The helper reads the complete tree twice through pinned directories. Both
passes must return the same paths, file kinds, and bytes. It rejects symbolic
links, hard links, FIFOs, other special files, duplicate classpath matches, and
size-limit violations. It sorts the complete result by UTF-8 path bytes after
the walk, so a file such as `foo.rs` sorts before `foo/bar.rs`. This comparison
detects changes during admission. It does not claim one atomic filesystem
snapshot against a hostile writer.

The helper enforces limits while it discovers and reads the tree. It does not
first collect an unbounded directory or response. Version 1 permits at most 128
real components in one classpath, 32 logical source-path components, 255 UTF-8
bytes in one component, 256 files and 8,448 total entries per crate, 2 MiB per
file, 16 MiB per crate, 32 MiB across all selected crates, and a 40 MiB response.

The helper returns a typed binary response with logical paths and copied file
bytes. Haxe then performs an independent check. It checks the exact manifest,
tree shape, text format, path grammar, file limits, order, and hashes.

The process runner drains stdout and stderr at the same time. It applies fixed
byte limits and a 15-second deadline. The deadline stays active until the child
has exited and both output pipes reach end-of-file. A termination signal is a
failure even when the numeric exit code is zero. Any stderr, partial result,
invalid frame, nonzero exit, signal, timeout, or runner exception discards all
returned bytes and closes the process, pipes, timer, and event loop.

Haxe 4.3.7 declares `eval.luv.Process.kill()`, but its eval runtime omits the
method binding. The runner derives a PID only from its open process watcher.
It keeps that watcher open until the exit callback reaps the child.

The current packaged helper supports Apple Silicon macOS only. The portable
Haxe policy can be reused for another host, but that host must first provide and
prove its own exact packaged binary and native facade. Windows needs a separate
host implementation.

The current proof uses the reviewed Git source package. One command rebuilds the
helper through Haxe/Metal and locked Cargo, then compares the fresh bytes with
the packaged binary:

```text
npm run test:support-crate-admission-package
```

The check also verifies Git mode `100755`, file mode `0755`, the hard-coded
SHA-256 digest, the complete source-input digest, exact Haxe/Rust/Cargo tool
identity, and the locked dependency graph. The source-input identity includes
the real Haxe compiler, its standard library, `.haxerc`, scoped Haxe inputs,
and all checked-in Cargo dependency sources. The package directory contains
`binary-provenance.json`, `dependency-inventory.json`, and
`THIRD_PARTY_NOTICES.md`.

The build selects `aarch64-apple-darwin`, the Rust compiler, the linker, the
macOS SDK, and the deployment target. It clears Haxe path/cache overrides and
Rust flags. It rejects a caller-provided `HAXE_BIN`. Cargo gets a new empty home
directory and reads only the checked-in vendor tree while offline. The evidence
records these inputs. The published dependency graph contains only packages
reachable for Darwin ARM64.

The Haxelib release ZIP does not include the helper yet. Release packaging
remains disabled until a packed-install test proves the same binary, executable
mode, provenance, dependency inventory, and notices outside the repository.

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

The focused fixtures prove the declaration grammar and request lifetime. They
also prove that admitted source creates no Cargo or Rust output in Stage 2B.

The macOS fixtures prove these boundaries:

- exact and parent-relative classpath admission.
- duplicate classpath rejection.
- nested Rust modules, including `src/platform/mod.rs`.
- symbolic-link, hard-link, extra-file, empty-directory, text, and manifest rejection.
- FIFO rejection without waiting for a writer.
- global UTF-8 path ordering, depth, entry, per-file, per-crate, total-source,
  and response limits.
- byte-exact request and response frames.
- clean exit, stderr, nonzero exit, signal, partial output, inherited-pipe,
  exception-cleanup, and timeout behavior.
- no machine path in the public diagnostic.
- no generated Cargo or Rust output after successful source admission.

The warm compiler-server fixture uses this sequence:

```text
safe -> valid but unavailable -> safe -> valid but unavailable
```

The two safe compiles produce byte-identical `src/main.rs`. Each rejected
request leaves the complete accepted output tree unchanged. Invalid field, inline-record-field,
type-parameter (including local generic functions and overloads), local record,
function-argument,
typedef-field, and abstract-field placements remain rejected. The packaged
compiler reaches the same stable source-admission diagnostic and creates no
Rust output.

A second warm-server fixture performs admitted requests from two different
caller directories. It also places a fake helper under a caller classpath. All
three requests reach the same Stage 3 stop, and the fake helper never runs.
This proves that request working directories and classpaths do not replace the
package helper anchor.

The reconciled independent architecture review and local decision matrix are
in [the original Oracle disposition](oracle-contained-unsafe-support-crate-disposition.md).
The later [source-admission disposition](oracle-support-crate-source-admission-disposition.md)
explains the Stage 2 split and the native helper boundary.
