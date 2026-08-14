# Support-crate source admission: local Oracle disposition

Oracle request: `orq_20260813T184955Z_060afb9d`

Local processor: `gpt-5.6-sol` at `xhigh`

Consultation mode: planning

## Outcome

Keep the Oracle's central recommendation, with the qualifications in this
document.

The current work must split into two stages:

1. Stage 2A parses the Haxe declaration and builds an immutable request plan.
2. Stage 2B admits exact source bytes through a small, one-shot native helper.

Stage 2A does not read the filesystem. It does not claim that source bytes are
safe, present, unique, or immutable.

Stage 2B must not use ordinary path checks. It must open each child relative to
an already open parent directory. The helper must read bytes from the same file
handle that it validates.

This decision does not enable support-crate emission. Stage 2A ends with a
stable `source admission unavailable` diagnostic. Stage 2B ends with a stable
`emission disabled` diagnostic.

## Why this work exists

`@:rustSupportCrate` will connect a typed Haxe extern to a separate Rust library
crate. The generated application crate can then keep `unsafe` Rust forbidden.

The compiler must copy only the reviewed Rust source that belongs to the
declaration. It must reject links, special files, nested Cargo projects, and
unlisted assets.

An ordinary pathname does not identify one stable file. Another process can
replace any path component between a kind check and a later read.

For example, this sequence is unsafe:

```text
1. inspect support/src/lib.rs and observe a regular file
2. another process replaces support with a symbolic link
3. read support/src/lib.rs by pathname
```

The final read can return bytes from outside the reviewed source tree. The
earlier check does not authorize those bytes.

The safe sequence uses open handles:

```text
open trusted root
  -> open one classpath child from that root
  -> open one sourceRoot child from that classpath
  -> open src from that sourceRoot
  -> open lib.rs from src
  -> validate and read lib.rs through the same file handle
```

Each child lookup uses its open parent. A later rename does not change the
object that the parent handle identifies.

## Local baseline

The local checkout is commit `48da9cdc1558fbe297d7890788bf1a3f3d97a678`.
It is the merged Stage 1 support-crate reservation.

The current compiler rejects `@:rustSupportCrate`. It has no declaration
parser, source admission plan, helper protocol, or support-crate emission.

The accepted design already requires these properties:

- `sourceRoot` resolves through exactly one active Haxe classpath.
- The source tree contains only one canonical manifest and Rust library files.
- The compiler rejects links and special files without following them.
- The compiler reads admitted source bytes once into an immutable plan.
- Later output code does not reopen the source checkout.

The current Stage 2 description combines declaration parsing and source-byte
admission. That description cannot truthfully describe a parser-only change.

The current Haxe 4.3.7 eval APIs are path-based:

- `sys.FileSystem` exposes `stat`, `isDirectory`, and `readDirectory` by path.
- `eval.luv.File` exposes `NOFOLLOW`, `open(path, ...)`, `lstat(path)`, and
  `fstat(file)`.
- `eval.luv.Dir` opens and scans directories by path.
- `File.toInt()` exposes a descriptor value, but no public API opens a child
  relative to that descriptor.

`NOFOLLOW` on a complete path protects only its last component. It does not
protect an ancestor that another process replaces.

The existing `CargoMetaRegistry` and `RustExtraSrcRegistry` are not safe
templates for this feature. They use process-static state, path reads, and
different merge rules. `CargoMetaRegistry` also puts object fields in a map,
which can hide duplicate fields.

No implementation or test was added during this planning consultation. The
previous complete local harness result remains evidence for Stage 1 only.

## Oracle claim matrix

| Oracle claim | Disposition | Local evidence and consequence |
| --- | --- | --- |
| Haxe 4.3.7 cannot perform the required recursive read through its current public eval APIs. | Retained | The live APIs have final-component `NOFOLLOW`, path-based directory operations, and no `openat`-style child open. A Haxe-only path reader is prohibited. |
| Split Stage 2 into pure declaration planning and later source admission. | Retained | This split keeps the parser useful without calling it a byte plan. Stage 2A performs no filesystem operation. |
| Use one compiler-owned native helper for source admission. | Retained | A narrow helper is the smallest current seam for POSIX `openat` and Windows parent-handle operations. It is not a generic filesystem service. |
| Extend Haxe instead of adding a helper. | Deferred | A future Haxe API can replace the helper. That upstream project is larger and does not block this bounded facility. |
| Use a fixed binary protocol instead of JSON or a line protocol. | Retained | The boundary must remain strongly typed and bounded. JSON adds a broad `Dynamic` decoder boundary. |
| Start one helper process per compiler request and never keep a daemon. | Retained | A one-shot process limits retained state and makes compiler-server cleanup testable. |
| Prevent namespace substitution, but do not claim an atomic filesystem snapshot. | Retained | Handle-relative lookup prevents path replacement from redirecting reads. A writer with access to an open file object can still mutate it. |
| Perform bounded pre-read, post-read, and second-tree consistency checks. | Retained | These checks detect observed edits. They do not prove that an adversarial writer cannot change and restore all observed facts. |
| Reject all source-tree links and Windows reparse points. | Retained | The closed source bundle must not follow an alternate namespace. No platform can fall back to an ordinary path read. |
| Reject regular source files whose reliable link count is not one. | Retained for version 1 | This rule removes mutation through an external hard-link alias. An unsupported filesystem must fail closed. |
| Reject every linked component in an active classpath. | Requires a bounded prototype decision | Strict rejection is safest, but it can conflict with symlinked working-directory aliases. Stage 2B cannot enable until the trust-anchor behavior is proved. |
| Treat mount crossings as ordinary pinned directories. | Retained | The accepted design does not require one filesystem device. Stage 2B must not add an implicit `NO_XDEV` rule. |
| Fail when any active classpath cannot be safely classified. | Retained | An inaccessible or unsupported classpath cannot count as a missing candidate. Unique resolution requires complete classification. |
| Use POSIX component-relative `openat` traversal. | Retained as the POSIX design | The implementation must open one child name at a time and read from the validated handle. Full-path fallbacks are prohibited. |
| Use Windows parent-handle child opens and reject all reparse points. | Retained as a design hypothesis | The relevant Windows API shape exists. Exact flags, root forms, and filesystem behavior still require a native prototype. |
| Ship exact helper binaries inside haxe.rust. | Retained | The compiler must use one package-relative executable. It must not use `PATH`, a shell, a download, or a consumer-side build. |
| Trust the installed haxe.rust package and helper location during compilation. | Retained as a bootstrap assumption | The source-tree attacker does not control the compiler package. Defending against compiler-package replacement is a separate project. |
| Author the helper in Rust. | Retained for the first implementation | This helper is compiler bootstrap code. Generation by the consuming compiler creates a circular release dependency. |
| Use the proposed source and protocol budgets. | Retained as provisional defaults | The counts and byte limits are suitable starting values. Exact timeout and stderr limits require measured Stage 2B evidence. |
| Add stable support-crate diagnostics through `RustDiagnostic`. | Retained | The current direct `Context.error` bypasses the repository diagnostic contract. |
| Use a complete finite fixture matrix. | Retained by stage | Stage 2A owns grammar and warm-state fixtures. Stage 2B owns native races, protocol errors, host binaries, and package smoke. |

## Integrated plan

### Stage 2A: declaration request plan

Stage 2A will add `SupportCrateRequestPlan`. The name distinguishes declared
intent from admitted source evidence.

The parser will:

- accept one object argument on an `extern class` only;
- require exactly the five documented fields;
- reject missing, unknown, and duplicate fields;
- parse ordered object fields without a map conversion;
- validate the crate name and the `@:native` prefix;
- normalize `sourceRoot` into logical path segments only;
- reject absolute paths, host separators, empty segments, `.` segments, and
  `..` segments;
- validate the unsafe policy, targets, and exact registry dependencies;
- merge repeated declarations only after exact normalized equality;
- keep each declaration owner and source position;
- build privately owned, deterministically ordered collections;
- use request-local compiler state only.

Stage 2A will not call `FileSystem`, `File`, `eval.luv`, or a helper. It will
not store source bytes, file hashes, or resolved machine paths.

After successful parsing, the compiler will emit a stable diagnostic:

```text
HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE
```

The compiler will not change Cargo or Rust output.

The compiler must clear request-plan state before validation can stop a warm
compiler request. A safe request before and after a failed support declaration
must produce byte-identical output.

### Stage 2B: admitted source plan

Stage 2B will add one narrow port:

```text
admit(requestPlan, activeClasspaths) -> admitted source bundles or one typed error
```

Production will use one package-owned helper process. Pure compiler tests can
use an in-memory fake that already contains logical paths and bytes.

The helper request will contain only:

- the protocol version;
- ordered active classpaths with opaque IDs;
- declaration IDs;
- normalized `sourceRoot` segments.

The request will not contain commands, environment changes, Cargo text,
targets, dependencies, arbitrary paths, or output locations.

The helper response will contain only:

- the protocol version;
- each declaration ID;
- one selected classpath ID;
- sorted logical paths;
- exact source bytes;
- one closed error category when admission fails.

The response will not contain absolute paths, native error text, or file
identifiers.

The helper will pin directories, enumerate entries, reject links and wrong
kinds, and read each source file once. It will return one complete response and
then exit.

Haxe will independently validate the logical tree and exact manifest bytes.
Haxe will also validate UTF-8, line endings, byte limits, and response order.
Then Haxe will compute hashes and construct the final `SupportCratePlan`.

The final plan will own fresh copies of all arrays and byte buffers. It will
not share helper decoder buffers or retain a helper process.

After successful admission, the compiler will emit a stable diagnostic:

```text
HXRS-SUPPORT-CRATE-EMISSION-DISABLED
```

The compiler will not change Cargo or Rust output until Stage 3.

### Helper implementation boundary

The first helper will be a small Rust host tool. It can use exact, reviewed
operating-system binding crates. It must not expose a general native-operation
API.

The release process will build and package exact host binaries. The compiler
will locate the binary relative to the installed haxe.rust package.

The first intended host matrix is:

- Linux x86-64;
- macOS x86-64;
- macOS arm64;
- Windows x86-64.

Each host remains unsupported until its native race tests and installed-package
tests pass. A missing host binary cannot select a weaker code path.

The provisional protocol limits are:

- 32 declarations per compiler request;
- 256 files per support crate;
- 32 path segments below a source root;
- 2 MiB per source file;
- 16 MiB per support crate;
- 32 MiB total source bytes per compiler request.

Stage 2B must set exact frame, stderr, descriptor, and process-time limits
before the helper can run in production.

### Required Stage 2A evidence

Stage 2A requires these focused results:

- valid minimal and repeated-identical declarations;
- missing, unknown, and duplicate fields;
- invalid placement, crate names, native prefixes, roots, targets, and
  dependencies;
- exact-equality conflicts without union merging;
- proof that no filesystem or helper operation occurs;
- safe, rejected, safe, and rejected warm compiler-server sequences;
- unchanged Cargo and Rust output after all rejected declarations;
- source and installed-package compiler tests.

### Required Stage 2B evidence

Stage 2B requires these focused results:

- zero, one, and multiple classpath matches;
- inaccessible and unsupported classpaths;
- links or reparse points at every path depth;
- special files, forbidden entries, invalid bytes, and manifest mismatch;
- hard links and every resource limit;
- deterministic file-replacement, ancestor-replacement, rename, truncation,
  and directory-membership races;
- truncated, oversized, duplicated, reordered, or trailing protocol data;
- helper timeout, early exit, missing binary, and wrong binary version;
- request-local cleanup after a partial response or failed helper;
- cold and warm plan equality;
- source-checkout and installed-package equality;
- one exact package test on every claimed compiler host.

## Rejected alternatives

### `lstat` followed by a path read

Rejected. Another process can replace the checked entry or an ancestor before
the read.

### `realPath` followed by a prefix check

Rejected. This operation follows the mutable namespace and returns another
path string. It does not pin the object that supplies the bytes.

### Repeated path checks

Rejected. Another process can change the path between any two checks. It can
also restore the earlier name after the read.

### A generic command or filesystem helper

Rejected. The compiler needs one closed source-admission operation. A general
helper would create a larger native authority than this feature needs.

### A Haxe-generated helper in the first release

Deferred. A compiler-built helper can become a useful self-hosting proof later.
The first version must not depend on the feature that it helps the compiler
implement.

## Unresolved gaps and stop conditions

Stage 2A can start after this disposition is recorded. Stage 2B cannot enable
until these decisions have proving evidence:

- the exact classpath trust-anchor rule for symlinked working directories;
- the exact supported Windows root and filesystem forms;
- the exact protocol frame, stderr, descriptor, and timeout limits;
- the exact native dependency lock and host build process.

Stop Stage 2B if any supported host needs one of these fallbacks:

- a full-path child read;
- link or reparse traversal;
- a helper found through `PATH`;
- a shell command;
- a runtime helper download;
- a consumer-side helper build;
- an arbitrary-path request;
- a process-global plan or helper cache;
- absolute paths in plans, diagnostics, or durable evidence;
- a claim of an atomic snapshot against a hostile in-place writer.

The Oracle did not run repository tests or native prototypes. This disposition
retains only claims that match the current source and public Haxe APIs.
