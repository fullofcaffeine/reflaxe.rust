# Support-crate source-admission helper

## Why this executable exists

haxe.rust can generate application Rust that forbids all unsafe code. Some
operating-system features still need a small, separately reviewed Rust crate.
The compiler must copy that crate from the Haxe classpath before it can generate
a safe Cargo project.

Haxe 4.3.7 macro APIs read files by pathname. They cannot keep a directory open
and then open each child relative to that directory. A different process could
replace a pathname between a kind check and a later read.

This helper supplies that missing filesystem operation. It is a small local
compiler companion. It is not part of the GameCarry application, and it is not
the support crate that an application requests.

## What owns the behavior

The helper's policy is Haxe source in `src/supportcrate/helper`. haxe.rust Metal
generates the executable's Rust code. Haxe owns:

- the binary request and response protocol;
- classpath and source-root selection;
- the recursive tree walk;
- deterministic ordering;
- resource limits;
- two-pass change detection;
- closed error results.

The file `native/support_crate_admission_fs.rs` is a narrow safe-Rust facade.
It uses `rustix` to open a child relative to an already open directory. It
keeps that exact child descriptor for the later directory walk or file read.
It also checks file kinds and reads bounded regular files. It contains no
product rule, manifest rule, shell command, or `unsafe` block.

This split keeps the reusable logic in Haxe. One hand-authored safe-Rust facade
owns only the operating-system operation that Haxe 4.3.7 cannot express.

## What a pinned directory means

The helper first opens a directory and retains its file descriptor. This README
calls that open directory a **pinned directory**.

Each child open uses the retained parent descriptor. For example, the helper
opens `native`, then `sample_support`, then `src`, and then `lib.rs`. It does not
rebuild and reopen one full pathname for every step.

If another process renames `sample_support` after it was opened, the descriptor
still refers to the original directory. New child reads continue below that
original directory.

A pinned parent does not make a child name immutable. The helper therefore
opens each child once, relative to the pinned parent. It keeps the returned
descriptor instead of keeping only the name or inode number.

This detail is important. Some filesystems can reuse an inode number. A later
open by name could then select a replacement object with the same number. A
retained descriptor continues to refer to the object that the helper opened.

The helper uses that descriptor for the first traversal. It then performs a
second traversal from the pinned source root. The second traversal rejects a
name that now selects different paths, kinds, or bytes.

This works on the current Apple Silicon Mac through the Unix `openat` family.
Linux can use the same facade after it gets its own packaged-binary evidence.
Windows needs another native facade.

## End-to-end flow

1. A Haxe extern uses one valid `@:rustSupportCrate` declaration.
2. The compiler creates a request with classpath locators and logical source
   segments. The request does not grant filesystem authority by itself.
3. The compiler verifies the packaged helper's size, mode, and SHA-256 digest.
4. The helper opens every classpath one component at a time.
5. The requested source root must exist under exactly one classpath.
6. The helper opens each selected child once and retains its exact descriptor.
7. The helper reads the complete source tree twice through pinned directories.
8. Both reads must contain identical paths, kinds, and bytes.
9. The helper sorts the complete tree by UTF-8 logical-path bytes.
10. The helper returns one bounded binary response through stdout.
11. The compiler decodes and independently validates that response.
12. The compiler constructs and validates one immutable plan from the admitted
    bytes.

Stage 2B then deliberately discards that plan. It stops before publication and
reports
`HXRS-SUPPORT-CRATE-EMISSION-DISABLED`. Stage 3 will copy the admitted bytes into
the generated Cargo project.

## Files that can be admitted

The low-level helper reads a complete regular-file tree. It rejects:

- symbolic links;
- files with more than one hard link;
- FIFOs, sockets, devices, and other special files;
- invalid UTF-8 names;
- duplicate or ambiguous classpath matches;
- a tree that changes between the two complete reads;
- any resource-limit violation.

The compiler performs the higher-level checks. It admits only the exact
`Cargo.toml` and Rust-library shape described in
[`docs/support-crate-facility.md`](../../docs/support-crate-facility.md).

## Resource limits

The helper applies limits during discovery and reading. It does not first build
an unbounded list.

- Request: 1 MiB.
- Classpaths: 256.
- Real path components in one classpath: 128.
- Support-crate declarations: 32.
- Logical path depth: 32 components.
- UTF-8 bytes in one path component: 255.
- Files per crate: 256.
- Total tree entries per crate: 8,448.
- File bytes: 2 MiB.
- Source bytes per crate: 16 MiB.
- Source bytes across one request: 32 MiB.
- Encoded response: 40 MiB.

The compiler runner also limits stderr and enforces a 15-second wall deadline.
The deadline remains active until the child exits and both output pipes close.

Haxe 4.3.7 declares `eval.luv.Process.kill()`, but its eval runtime does not
bind that method. The runner gets the PID from its open process watcher instead.
It keeps that watcher open until the exit callback reaps the child. This rule
prevents exceptional cleanup from closing the watcher before child exit.

## Failure behavior

The helper writes either one accepted response or one closed rejection. It does
not write logs to stderr during a successful run.

The compiler discards all bytes after any uncertainty. This includes malformed
protocol data, stderr, a nonzero exit, a termination signal, a timeout, a pipe
failure, or an exception after process creation.

The two reads detect differences that are visible between those reads. They do
not create an atomic filesystem snapshot against a hostile writer.

The compiler hashes the helper before it executes the packaged pathname. The
installed haxe.rust directory is trusted. This stage does not claim that macOS
executes the same already-open inode that the compiler hashed.

## Build and verification

Build and publish the current-host helper into the package tree:

```sh
npm run build:support-crate-admission-helper
```

Rebuild it in a separate directory and verify the package:

```sh
npm run test:support-crate-admission-package
```

The second command requires all these facts to match:

- fresh Haxe/Metal and locked-Cargo bytes;
- packaged binary bytes and SHA-256 digest;
- filesystem mode `0755` and Git mode `100755`;
- the compiler's hard-coded digest;
- source-input and toolchain provenance;
- the Cargo lock, dependency graph, checksums, features, and licenses;
- the generated third-party notice inventory.

The package build does not use downloaded Cargo source directories. All locked
Cargo dependency sources are checked in under `vendor/`. Cargo gets a new empty
home directory for each build and runs offline against only that vendor tree.
The source-input digest covers every vendored byte and its source configuration.

The package build also rejects `HAXE_BIN`. It uses the repository Lix launcher
and the exact Haxe version in `.haxerc`. It clears Haxe path and cache overrides.
The evidence covers the launcher, the real Haxe executable, the Haxe standard
library, the scoped Haxe library files, and all local compiler sources.

When a reviewed Cargo dependency changes, regenerate the vendor tree before
the package build:

```sh
cargo vendor --locked --versioned-dirs \
  --manifest-path tools/support-crate-admission-helper/out/Cargo.toml \
  tools/support-crate-admission-helper/vendor
```

Review the vendor diff, its license files, and `Cargo.lock`. Then rebuild the
package and commit the new provenance, dependency inventory, and notices.

The package build supports `aarch64-apple-darwin` only. It selects the Cargo
target, Rust compiler, linker, macOS SDK, and deployment target explicitly. It
also clears Rust flags and disables incremental and network work. The build
rejects unreviewed ancestor Cargo configuration files.

The dependency inventory uses Cargo's Darwin ARM64 graph. It includes only
packages that the helper can reach for that target. Thus, Linux, Windows, and
Redox-only packages do not appear in the macOS notice file.

Run the behavior suites with:

```sh
npm run test:support-crate-admission-helper
npm run test:support-crate-admission-runner
npm run test:support-crate-boundary
```

## Explicit non-goals

This helper does not:

- run Cargo for the consumer;
- generate or publish application output;
- execute a shell or arbitrary command;
- download a helper or source bundle;
- accept product-specific policy;
- prove that unsafe Rust is semantically sound;
- provide Linux, Windows, or Haxelib package support in Stage 2B.

Keep these boundaries narrow when the helper evolves. New portable policy
belongs in Haxe. Add native code only when the target operation cannot be
expressed safely through the current Haxe and Metal surface.
