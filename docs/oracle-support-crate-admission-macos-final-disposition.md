# Stage 2B macOS final-review disposition

## Outcome

The local agent accepts the Oracle result as advisory review evidence.

Disposition: request changes before the Stage 2B pull request.

The architecture remains accepted. The helper policy and protocol stay in
Haxe and compile through haxe.rust Metal. One small safe-Rust facade continues
to own the operating-system directory calls that Haxe 4.3 cannot express.

The current implementation must not be committed as the completed Stage 2B
result yet. The review found bounded correctness and evidence gaps. They do
not require a different architecture.

## Local verification

The local agent checked the material findings against the frozen worktree.

### Retained: complete-path ordering

The helper sorts names inside each directory. It then visits a directory before
the next sibling. This creates depth-first order, not global logical-path order.

A direct helper probe used this valid tree:

```text
src/foo.rs
src/foo/bar.rs
```

The helper returned this order:

```text
src/foo
src/foo/bar.rs
src/foo.rs
```

The protocol and independent validator require `src/foo.rs` before
`src/foo/bar.rs`. The response therefore cannot cross the compiler boundary.

One Oracle detail needs correction. The Metal response writer does not check
global order. It writes the invalid order. The compiler decoder rejects it.
This correction does not change the finding or required repair.

### Retained: limits apply too late

The Rust facade collects and sorts a complete directory before Haxe checks the
entry count. The Haxe traversal does not enforce the protocol's 32-segment
depth limit. Per-crate source limits exist, but helper-global source and encoded
response limits do not.

These are real resource-boundary gaps. A compiler-side rejection does not bound
work or retained memory inside the helper.

### Retained: signaled exit can look successful

The Haxe runner ignores the libuv termination-signal value. A local probe wrote
one byte and then sent `SIGTERM` to itself. The current runner classified that
process as `Completed`.

A clean result must require both exit status zero and termination signal zero.
Timeout must remain the reported result when the runner sends the signal.

### Retained: warm package anchor is not proven

`RustCompiler` stores the raw source-position filename. The locator converts it
to an absolute path later. If the stored filename is relative, a later compiler
request can resolve it against a different working directory.

The current warm test exercises state cleanup, but it does not perform
successful source admission from two request working directories. The package
root must become one validated absolute value when the executing compiler class
initializes. Active classpaths must not participate in this lookup.

### Retained: Git binary evidence needs one mechanical gate

The current bytes have a valid manual three-way comparison:

```text
fresh Metal build
  == checked-in darwin-arm64 binary
  == hard-coded SHA-256
```

The repository does not yet enforce that relation with one command. GameCarry
will consume the Git/Lix package, including this binary. Therefore, Git-mode
provenance, executable mode, exact build inputs, dependency licenses, notices,
and SBOM records belong in this stage.

Haxelib ZIP inclusion and publication remain later release work.

### Retained: evidence policy needs reconciliation

The earlier disposition still describes Linux-first evidence. Its addendum
changes the host order but leaves conflicting requirements in later sections.
The final document must state the Mac-first contract directly.

The updated contract will:

- make macOS parent death an explicit nonclaim;
- require direct-child timeout, kill, and reaping behavior;
- require Git/Lix package proof instead of Haxelib ZIP proof for Stage 2B;
- use the recursive descriptor invariant plus representative deterministic
  race barriers;
- retain successful warm admission from different working directories;
- retain exact Git binary provenance and exception cleanup.

### Retained: bounded adjacent repairs

The following repairs belong in the same finite boundary:

- Reject a FIFO before a blocking read. Use a descriptor-relative no-follow
  kind check, a nonblocking open, and the existing post-open metadata check.
- Keep the wall deadline active until the child exits and both output streams
  reach EOF.
- Centralize post-spawn cleanup and add an injected-exception fixture.
- State that two complete observations reject differences visible between
  those observations. Do not claim an atomic snapshot or detection of every
  transient change.
- State the admission-time parent meaning of a `..` classpath component.
- Reject `componentIndex == MAX_CLASSPATH_COMPONENTS` because the index is
  zero-based.

## Accepted boundaries

The review supports these current decisions:

- The safe-Rust filesystem facade is the smallest correct exception to
  Haxe-authored Metal logic.
- Descriptor-relative child opens are the correct source-containment seam.
- Representative nested-directory and file race barriers are sufficient when
  they prove the shared recursive primitive. A test at every depth is not
  required.
- Verification followed by pathname execution is acceptable only because the
  haxe.rust package and macro process are trusted. Stage 2B does not claim that
  it executes the same open inode that it hashed.
- Linux, Windows, Haxelib publication, Stage 3 emission, hostile macro
  sandboxing, and atomic filesystem snapshots remain deferred.

## Finite repair plan

1. Canonicalize complete helper trees by encoded full logical path. Add the
   `foo.rs` and `foo/bar.rs` regression through helper and compiler boundaries.
2. Enforce directory-entry, name-byte, depth, request-global source, and
   encoded-response limits before excess work or retention.
3. Reject every nonzero termination signal and keep the deadline through full
   stream completion.
4. Anchor the package root once as an absolute validated value. Prove warm
   successful admission across different working directories and fake helper
   classpaths.
5. Add one build-verification command for source, lock, binary, digest, mode,
   provenance, licenses, notices, SBOM, and Git/Lix checkout behavior.
6. Add prompt FIFO rejection, centralized exception cleanup, nested-directory
   and file-swap barriers, and the component-index correction.
7. Reconcile the public documentation and prior disposition with the exact
   Mac-first Stage 2B contract.
8. Rerun focused suites, guards, package proof, the full local harness, and one
   narrow closure review.

Stop and reopen architecture review only if a repair requires a full-path child
open, a classpath search for the helper, an unbounded native buffer, a shell or
download fallback, process-global request state, or a broader handwritten Rust
policy layer.

## Local repair status

All finite repairs above are implemented in the current candidate:

- complete UTF-8 path sorting handles `foo.rs` and `foo/bar.rs` correctly;
- discovery enforces depth, entry, name-byte, source-byte, and response limits
  before excess retention;
- FIFOs and other special files fail before a blocking read;
- signals fail, and the deadline stays active through output EOF;
- one post-spawn exception path closes all process resources;
- the package root is anchored once and survives warm requests from different
  caller directories;
- a fresh Haxe/Metal and locked-Cargo build matches the packaged binary, digest,
  modes, input identity, dependency inventory, licenses, and notices;
- the public contract now states the trusted package, two-pass observation,
  macOS, Git/Lix, and deferred Haxelib boundaries directly.

These statements are implementation status, not independent closure approval.
The focused suites and the complete local harness passed on the unchanged
candidate. The complete harness took 6,349 seconds and included the full Metal
policy matrix, compiler-server tests, package tests, generated examples, and
native parity. One narrow independent closure review remains required.

## Deferred work

Stage 3 owns Cargo integration and transactional publication of admitted
support source. Linux needs an exact VM-built binary and Linux-specific
process evidence. Windows needs a separate host design. Haxelib needs truthful
ZIP mode and release evidence. None of these deferred items weakens the current
Mac and Git/Lix repair requirements.
