# Oracle disposition: final Stage 2B package boundary review

Oracle request: `orq_20260814T121517Z_e6d03150`

Reviewed commit: `b9d06bc61e7365d53dde690cf4b05cb81f99f2ad`

Local processor: `gpt-5.6-sol` at `xhigh`

## Local conclusion

The Oracle found three real blockers. I retained all three findings. I did not
treat the response as permission to merge. I reproduced two failures directly
and confirmed the third from the package builder's input boundary.

The repair keeps the accepted architecture. Haxe and Metal still own the
protocol, traversal, limits, ordering, and two-pass comparison. A narrow
safe-Rust facade still owns only filesystem operations that Haxe 4.3.7 cannot
express. The package builder now owns exact compiler and dependency inputs.

## Finding dispositions

### Retained: a child was reopened by name

The old `PinnedChild` stored the parent descriptor, name, device, and inode.
The later read reopened that name and compared the new identity. A filesystem
can reuse an inode, so this was not permanent authority for the inspected
object.

The facade now opens each child once with `openat` and `NOFOLLOW`. `PinnedChild`
retains that exact descriptor. A directory walk shares it. A file read uses a
descriptor duplicate, so it cannot select another pathname object.

The deterministic replacement fixtures now pause after exact child acquisition.
The first traversal continues on the original object. The second traversal
then returns `SOURCE_CHANGED` because the namespace changed.

### Retained: Cargo compiled ambient cache bytes

The old package build used the caller's `CARGO_HOME`. Cargo can reuse mutable
unpacked registry sources without checking every source byte again. The lock
and dependency inventory therefore did not prove the bytes in the executable.

All locked Cargo sources are now checked in under the helper's `vendor/`
directory. The package build creates a new empty Cargo home for each run. It
uses an explicit source-replacement configuration and runs offline. The source
identity covers every vendored byte and the replacement configuration.

The regression supplies an ambient Cargo home with a modified `rustix` source.
The package check remains green because that cache is outside Cargo's input.

### Retained: Haxe identity was caller-controlled

The old build accepted `HAXE_BIN` and recorded only its reported version. A
wrapper could report Haxe 4.3.7, call real Haxe, and then change generated Rust.

The package build now rejects `HAXE_BIN`. It runs the repository Lix launcher
with a small environment that omits Haxe path and cache overrides. `.haxerc`
selects one scoped Haxe version. Provenance and source identity cover the Lix
launcher, the real Haxe executable, the complete Haxe standard library, the
scoped library descriptors, and the local compiler sources.

The hostile regression uses the exact spoof described by Oracle. The build
rejects it before generation.

## Verification completed before ledger processing

- `npm run test:support-crate-admission-helper`: 21 of 21 passed.
- `npm run test:support-crate-admission-runner`: 10 of 10 passed.
- `npm run test:support-crate-boundary`: 16 of 16 passed.
- `npm run test:support-crate-admission-package`: passed with the hostile Haxe
  and poisoned Cargo controls.
- `node scripts/ci/native-facade-manifest-check.js --check`: passed.
- `node test/scripts/package-input-cleanliness.test.js`: passed after removal
  of one unrelated generated Python cache file.
- `git diff --check`: passed.

The rebuilt Darwin ARM64 helper digest is
`8bd0cab5f86501f92b6600472867542e48252d8ffa3606c3061408115bf124d5`.

## Remaining proof

The repaired bytes still require the complete local harness on one committed,
unchanged revision. Repository policy also requires a new exact-candidate
Oracle closure review because this repair materially changes the reviewed
filesystem and package-input boundaries. Stage 3 emission, Linux, Windows,
Intel macOS, and Haxelib packaging remain outside this change.
