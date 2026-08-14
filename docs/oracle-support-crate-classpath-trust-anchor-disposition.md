# Support-crate classpath trust anchor: local Oracle disposition

## Implementation addendum

This document records the design decision before implementation. The Oracle
recommended Linux x86-64 as the first host. The requester later required the
first working proof on the current Apple Silicon Mac.

The implementation therefore enables macOS ARM64 first. The helper uses
`openat`-style calls through the safe `rustix` API on macOS. It pins each
parent directory before it opens the next child. The focused tests prove
relative parent traversal, nested files, and link rejection on this Mac.

The helper is not handwritten application Rust. Its protocol, traversal, and
admission logic are Haxe compiled by haxe.rust Metal. One small safe-Rust
facade exposes the operating-system calls that Haxe 4.3.7 does not provide.

Linux remains fail-closed until a Linux VM builds and tests an exact packaged
binary. Thus, the host-order statements below are historical plan records.
This addendum supersedes only that order. The authority rules and stop
conditions remain unchanged.

## Outcome

Stage 2B will use one transient binding from each classpath ID to its Haxe path
string. The binding exists only in the request to the package-owned helper.

The path string is a locator. It does not prove filesystem identity. The helper
gets authority only after it opens a directory and keeps its file descriptor.

The first native tracer will support Linux x86-64 only. Other hosts will stop
before helper discovery. They will not use an ordinary path fallback.

This decision accepts **admission-time identity**. This term means the exact
directory and file objects that the helper opened while it admitted source.
It does not mean the objects that Haxe used earlier while it typed Haxe code.

This distinction is acceptable for Stage 2B. The final source digest identifies
the exact Rust bytes that the helper returned and Haxe accepted.

## Why this review was necessary

Stage 2A created an immutable plan from `@:rustSupportCrate`. That plan contains
logical names and policy. It contains no filesystem path or source byte.

The earlier Stage 2B design gave the helper only opaque classpath IDs. An opaque
ID is a request-local number such as `classpath #2`. It cannot locate a real
directory.

A Haxe 4.3.7 probe showed the missing fact. `Context.getClassPath()` returns
path strings. The result included relative, absolute, empty, and standard-library
entries. It did not include a directory handle.

For example, Haxe can return this active classpath:

```text
../shared/src/
```

The Haxe adapter will give it a request-local ID:

```text
classpath #0 -> ../shared/src/
```

Only the private helper request contains the right side. Public diagnostics and
durable plans use `classpath #0`. The helper response also uses this ID.

The helper opens the inherited current directory. Then it opens `..`, `shared`,
and `src` one component at a time. Each successful open returns a pinned
filesystem object.

This sequence keeps normal Haxe classpath behavior. It also prevents a later
change to an opened ancestor from redirecting the remaining child opens.

## Local baseline before the Oracle response

The local review established these facts before it read the response:

- Stage 2A is merged at `c1dd6a218a6c252c954b800808bef4c6b2d1ad63`.
- Stage 2A reads no support-crate source and emits no Cargo or Rust output.
- Haxe 4.3.7 exposes classpaths as strings through `Context.getClassPath()`.
- Haxe has no public macro API that transfers open classpath directory handles.
- A transient locator can work only if the helper opens and pins every object.
- The exact behavior for empty, relative, and linked paths was not settled.

The Oracle request was `orq_20260814T011859Z_f712c070`. The ledger recorded a
complete GPT-5.6 Pro response with valid model proof. The local processing model
is `gpt-5.6-sol` at `xhigh`.

## Claim matrix

| Oracle claim | Local disposition | Evidence and consequence |
| --- | --- | --- |
| Add a private classpath ID-to-path binding. | Retained | Haxe 4.3.7 supplies only path strings. Opaque IDs alone cannot locate roots. |
| Treat the path as a locator, not authority. | Retained | Authority begins with a successful parent-relative open and a retained descriptor. |
| Claim admission-time identity only. | Retained | The helper starts after Haxe typing. No current API can prove typing-time object identity. |
| Require an upstream Haxe handle API for typing-time identity. | Retained | A request-scoped directory capability is necessary for that stronger contract. |
| Add one synthetic empty classpath when the captured list has none. | Retained | `Common.find_file` adds `""` as the final fallback. The adapter must model the same search. |
| Use the inherited current-directory object for empty and relative entries. | Retained | The helper opens `.` directly. It never sends or reconstructs a current-directory path. |
| Use an open `/` descriptor for absolute Linux entries. | Retained | Each later component is opened relative to the prior descriptor. |
| Reject transmitted classpath components that are symlinks. | Retained | Every component becomes the final component of one `openat` call with `O_NOFOLLOW`. |
| Reject `..` in an active classpath. | Rejected | Haxe accepts parent-relative classpaths and real projects use them. A classpath is a locator, not a containment root. The helper must open the actual `..` component. |
| Continue to reject `..` in authored `sourceRoot`. | Retained | `sourceRoot` is a contained logical path below each classpath root. It has a different contract. |
| Treat any unreadable, linked, or wrong-kind active classpath as fatal. | Retained | The helper cannot prove unique resolution when it cannot classify an active entry. |
| Reject two matching classpath IDs, including aliases to one object. | Retained | The public contract requires exactly one active classpath match. Object aliasing does not erase the second match. |
| Return file records only. | Rejected as incomplete | Haxe cannot independently reject a forbidden empty directory when the response omits directories. Protocol v1 must return directory and file entries. |
| Use a closed binary protocol. | Retained with correction | The response carries a sorted typed tree. It does not carry only files. |
| Locate the helper from an already-loaded package type position. | Retained with correction | The implementation must use the already-loaded `RustCompiler` type. It must not add a new logical classpath search for a marker. |
| Use `Context.resolvePath` to locate the helper. | Rejected | A fresh lookup can select a higher-priority shadow from an active classpath. |
| Enable Linux x86-64 first. | Retained | Linux has the required parent-relative APIs. This slice does not claim macOS or Windows support. |
| Enable macOS or Windows from the current design alone. | Rejected | Firmlinks, reparse points, roots, and inherited-directory behavior need host-specific native evidence. |
| Use a request-local runner with concurrent bounded pipe handling. | Retained | Sequential pipe handling can deadlock when an invalid helper fills another pipe. |
| Prove cooperative compiler-request cancellation. | Deferred | Haxe 4.3.7 exposes no public compiler-request cancellation callback to this macro. Timeout, exception, parent-death, close, kill, and reap behavior remain required. |
| Make all proposed resource numbers permanent protocol policy now. | Deferred in part | Source and frame ceilings can start as closed constants. Wall, CPU, address-space, and descriptor limits need measured Linux evidence. |
| Package an exact helper binary and inventory it. | Retained | The compiler cannot use `PATH`, a download, an environment override, or a consumer-side build. |
| Trust the loaded haxe.rust package and the macro process. | Retained | This trust boundary was already accepted. Hostile macro containment is a separate compiler-sandbox project. |

## Integrated authority model

Five owners act in order:

1. The Haxe declaration owns the requested crate and its logical `sourceRoot`.
2. Haxe owns the ordered classpath strings for the current compiler request.
3. The helper opens and pins the directories that can supply source bytes.
4. The helper returns one closed logical tree with copied bytes.
5. Haxe validates that tree, renders the expected manifest, and computes hashes.

The final digest identifies bytes. It does not identify a pathname or inode.

The helper can prevent a path change from redirecting child opens after it pins
an ancestor. It can also validate and read a file through one descriptor.

The helper cannot prove one atomic snapshot against an active in-place writer.
It also cannot contain hostile macro code that already runs in the compiler.

## Transient protocol

Protocol v1 will use fixed little-endian fields and bounded lengths. It will not
use JSON, reflection, `Dynamic`, line parsing, or native error text.

The request will contain:

- one magic value and protocol version.
- closed flags and payload length.
- ordered classpath IDs and exact private path bytes.
- stable declaration IDs.
- normalized `sourceRoot` segments.

The response will contain:

- one magic value and protocol version.
- one success or classified-error status.
- each declaration ID and selected classpath ID.
- sorted directory and file records.
- logical path segments for each record.
- exact bytes for file records only.

A tree record will have a closed kind: `directory` or `file`. Haxe will reject
unknown kinds, duplicates, invalid order, missing parents, and trailing data.

The response will not contain:

- a machine path.
- a native error number or message.
- a device or inode value.
- a helper path.
- captured standard error.
- a backtrace.

The helper will return directory records so Haxe can reject hidden or forbidden
empty directories. Native file-kind and link checks remain helper-owned because
Haxe does not receive operating-system handles.

## Linux classpath rules

The helper will preserve Linux path semantics for active Haxe classpaths:

- `""`, `.`, and `./` start at the inherited current-directory object.
- A relative path starts at that same object.
- An absolute path starts at the helper's open `/` descriptor.
- Empty and `.` components are no-ops.
- A `..` component opens the actual parent directory from the current descriptor.
- Repeated and trailing `/` characters do not change the selected object.
- A transmitted symlink component is an error.
- NUL, control characters, backslash, invalid UTF-8, and over-budget input are errors.
- A leading `//` or more is outside protocol v1.

The helper will not normalize `..` as text. It will perform the parent open at
that exact point. This preserves mount and directory-object behavior.

Authored `sourceRoot` remains relative and contained. It continues to reject
empty, `.`, `..`, backslash, colon, and NUL segments.

## Trusted helper location

The compiler must not search the active classpaths for the helper executable.

The implementation will query the position of the already-loaded
`reflaxe.rust.RustCompiler` type. It will derive one fixed package-relative
binary location from that source position.

This seam needs a focused prototype before the native reader is enabled. The
prototype must cover these cases:

- a source checkout.
- an installed Haxelib package.
- a relative checkout.
- a higher-priority fake helper or marker classpath.
- cold and warm compiler requests.
- different warm-request working directories.

If the query can load a new shadow instead of returning the executing compiler
type, stop this design. Use a smaller package-owned bootstrap seam or extend
Haxe.

The compiler will start the exact package-relative binary directly. It will
not invoke Cargo, a shell, a download, `PATH`, or an environment override.

## Request-local process behavior

The Haxe runner will start zero or one helper per compiler request. An empty
support-crate plan starts no helper.

The runner must drain standard output and standard error concurrently. It must
also write the request and wait for the process without a pipe deadlock.

The runner will enforce bounded frames and one parent wall deadline. On an
error, it will close the pipes, kill the child once, reap it, and erase partial
buffers.

The helper will set a parent-death signal on Linux. This protection removes an
orphan when the compiler process dies. A deterministic fixture must cover the
startup race around the parent-death setting.

The first contract will not claim cooperative compiler-request cancellation.
If Haxe adds a real callback, a later change can connect it to the same cleanup
path.

## One complete implementation sequence

Stage 2B remains one feature and one final pull request. These checkpoints
prevent speculative native code from becoming authority:

1. Amend the public design with this disposition and the admission-time claim.
2. Add pure typed protocol models, codecs, golden frames, and malformed frames.
3. Add the complete tree response and an in-memory fake admission port.
4. Prove the `RustCompiler` source-position locator in source and package modes.
5. Add a Linux x86-64 host and capability gate before helper discovery.
6. Add the package-owned Rust helper with closed protocol decoding.
7. Add descriptor-relative classpath and source-tree traversal.
8. Add deterministic race barriers around directory opens and file reads.
9. Add the bounded Haxe process runner and cleanup fixtures.
10. Add Haxe's independent tree, manifest, text, order, budget, and hash checks.
11. Integrate the admitted immutable plan before Cargo and extra-source registries.
12. Stop successful admission at `HXRS-SUPPORT-CRATE-EMISSION-DISABLED`.
13. Add the exact helper binary, digest, mode, provenance, notices, and SBOM to packaging.
14. Run the focused suite, package smoke, repository guards, full local harness, and independent review.

The checkpoints are development order. They are not separate partial releases.

## Required evidence

The final pull request must include these results:

- empty, relative, parent-relative, and absolute classpath success.
- duplicate strings, `""` plus `./`, and object aliases as ambiguous matches.
- inaccessible, linked, wrong-kind, malformed, and over-budget classpaths.
- a link swap at every classpath, `sourceRoot`, directory, and file depth.
- replacement before and after each parent descriptor opens.
- hard-linked source and manifest rejection.
- deterministic mutation during read and during the second tree pass.
- all directory records, including forbidden empty directories.
- wrong magic, version, flags, order, kind, count, length, and trailing bytes.
- partial output, excess output, standard-error output, timeout, and early exit.
- child cleanup after Haxe exceptions and parent process death.
- zero or one helper process for one or many declarations.
- independent Haxe rejection of a structurally valid but invalid helper tree.
- safe, rejected, safe warm requests with different working directories.
- source checkout and installed-package parity.
- package inventory, executable mode, digest, provenance, notices, and SBOM.
- no path, native error, frame, or captured standard error in durable output.
- no Cargo or Rust output after successful Stage 2B admission.

Use deterministic barriers for race fixtures. Do not use timing sleeps as race
evidence.

## Stop conditions

Stop Stage 2B if any implementation needs one of these fallbacks:

- a fresh `Context.resolvePath` lookup for the helper.
- a full-path open for a source child.
- `realpath` or prefix checks for source authority.
- a path normalization that changes valid Haxe classpath behavior.
- a symlink-following fallback.
- a second helper attempt after an error.
- a helper from `PATH`, a shell, a download, or a consumer build.
- a process-global path, plan, response, process, or byte cache.
- an unbounded pipe, buffer, descriptor set, or deadline.
- a raw path or native error in durable evidence.
- a claim of atomic source-tree state.
- a claim of typing-time filesystem identity.
- a claim of cooperative cancellation without a Haxe cancellation API.

Stop the helper locator if a classpath shadow can redirect it away from the
already-loaded haxe.rust compiler package.

Stop Linux enablement if the runner cannot prove deadlock-free cleanup and child
reaping. Do not add a generic launcher process as a workaround.

## Host scope and GameCarry consequence

The first native tracer enables only Linux x86-64. macOS and Windows remain
explicit follow-up host proofs.

This Linux tracer does not yet unblock a native macOS GameCarry build on the
current development machine. A Linux VM can exercise source admission and
cross-platform pure planning. A later macOS helper proof remains necessary for
local macOS compilation.

The repository must not describe Stage 2B as general host support after the
Linux tracer passes.

## Verification completed during reconciliation

The local agent completed these read-only checks:

- It read the complete captured Oracle response and its completion sentinel.
- It verified the request owner, mode, model, model proof, and reasoning floor.
- It inspected the exact haxe.rust revision from the submitted packet.
- It inspected Haxe 4.3.7 `Context.getClassPath()` and `Common.find_file`.
- It verified that `Common.find_file` adds the empty classpath fallback.
- It verified that Haxe returns an accepted parent-relative classpath with `..`.
- It inspected Haxe eval `sys.io.Process` and found no request-cancellation callback.
- It inspected the release package, ZIP allowlist, and installed-package smoke.
- It confirmed that the current helper package and inventory rules do not exist.

No helper was built. No native race fixture ran. No Stage 2B test result is
claimed.

## Unresolved evidence

The implementation must still prove these two medium-confidence seams:

1. The loaded `RustCompiler` source position selects the trusted package in all
   source, installed, shadow, and warm-request fixtures.
2. The Haxe process runner drains pipes and reaps the helper without a deadlock.

The Linux prototype must measure process limits before the public protocol
makes them permanent.

No owner decision blocks the Linux tracer. Existing repository policy already
accepts admission-time identity and trusts the haxe.rust package and macro
process. A stronger identity or hostile-macro contract requires a separate
upstream Haxe or compiler-sandbox project.
