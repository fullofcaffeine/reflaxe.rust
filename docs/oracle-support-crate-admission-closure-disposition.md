# Stage 2B exact-candidate Oracle disposition

## Outcome

The GPT-5.6 Pro closure review requested changes. The local agent retains the
helper architecture and retains six implementation/evidence findings. One
reported blocker is a review-request identity error that the local agent
introduced; it is not a defect in the committed source tree.

The reviewed local commit is exactly:

`3f9dc0978435bacd704fc03713c59bab25bd0f61`

The Oracle request is
`orq_20260814T084456Z_5cb2338d`. The response is advisory evidence. This
document records the local disposition before any repair begins.

## Finding dispositions

### 1. Requested SHA and packet SHA differ

**Disposition: rejected as a code blocker; retained as a review-packet error.**

The local agent wrote
`3f9dc097ce7a949c21920784e20bb12a3b3f56c3` in the prompt after knowing only
the short commit name `3f9dc097`. That full object does not identify the local
commit. The packet correctly captured the real `git rev-parse HEAD` value,
`3f9dc0978435bacd704fc03713c59bab25bd0f61`.

Therefore, Oracle reviewed the actual committed source included in the packet,
but the request falsely claimed a different exact object. A replacement review
must obtain the full SHA mechanically and compare it with the packet manifest.
It must also carry the packaged executable as separate immutable evidence when
the text packager cannot include binary bytes.

### 2. Resource limits are not always early

**Disposition: retained.**

Local inspection confirms all four cases:

- discovered names can exceed the protocol's 255-byte segment limit;
- recursive calls retain unreserved ancestor name vectors;
- the file-count and per-crate byte checks occur after a file read; and
- the declared 128-component classpath limit is not enforced before all opens.

The repair must use one traversal-wide reservation budget, reject overlong
names before retaining them, include the remaining per-crate allowance in each
read, reject before opening the 257th file, and enforce the component limit in
both compiler and helper boundaries.

### 3. Exceptional cleanup can close before reaping

**Disposition: retained.**

The exception path sends a raw-PID kill and closes the process handle before
the exit callback. The repair must signal the owned process handle, keep its
watcher alive, drive bounded cleanup until exit is observed, and test repeated
failure in a long-lived process.

### 4. Output accounting can overflow

**Disposition: retained.**

`SupportCrateAdmissionReadState` adds a buffer length to a signed `Int` before
it checks the limit. After overflow, retention can resume even though success
remains impossible. The repair must use a permanent exceeded state and
remaining-capacity arithmetic that never computes an overflowing sum.

### 5. Nested-directory and file-swap barriers are absent

**Disposition: retained.**

The descriptor-relative implementation looks sound, but the earlier accepted
proof plan explicitly required deterministic barriers at the child-directory
open and file open transitions. Current tests cover whole-pass content change
and source-root replacement only. Add the missing barriers and adversarial
replacement matrix before claiming complete race evidence.

### 6. Build provenance does not bind the effective Cargo build

**Disposition: retained.**

The build script records one selected Rust compiler but lets Cargo inherit
ambient compiler, wrapper, flags, linker, target, SDK, and Cargo configuration.
It can therefore describe a compiler that did not create the binary. The
repair must create one controlled Darwin ARM64 build environment, reject or
record every build-affecting input, and prove Cargo used the recorded tools.

### 7. Dependency evidence is not target-specific

**Disposition: retained.**

The current inventory includes Linux, Windows, and Redox packages while it
claims to describe the packaged macOS helper. Filter Cargo metadata for
`aarch64-apple-darwin`, traverse only nodes reachable from the helper root, and
generate notices from that exact package set.

## Minor findings

All four minor findings are retained:

- say that Stage 2B constructs, validates, and then discards the immutable plan;
- move closed source-root grammar and resource checks into the typed planner
  while keeping protocol/helper checks as defense in depth;
- remove the unsupported Linux package-build mapping from this commit; and
- replace locale-dependent evidence sorting with UTF-8 byte ordering.

## Local repair and acceptance plan

Keep the current Haxe/Metal helper and narrow safe-Rust filesystem facade.
Repair only the bounded limits, runner cleanup/accounting, test barriers, and
package-evidence owners above. Do not add Stage 3 mutation or another platform.

After repair:

1. Run the new focused limit, cleanup, race, and package regressions.
2. Run all existing Stage 2B focused suites and guards.
3. Rebuild and verify the exact packaged helper and target-specific evidence.
4. Run the complete local harness once on the exact committed candidate.
5. Create a new Oracle packet whose requested SHA is read from Git, whose
   manifest has the same SHA, and whose evidence includes the packaged binary,
   mode, and digest.

The response introduces no owner decision that requires changing the accepted
architecture or expanding the feature scope.
