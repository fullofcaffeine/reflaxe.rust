# Release licensing review

## Purpose

This page records what source and dependency information the release package
contains, what the build checks mechanically, and which questions still need a
qualified legal answer. It deliberately does not claim that the package or a
generated application is legally approved.

## What the package now proves

The release ZIP contains:

- the reflaxe.rust GPL version 3 license text;
- Reflaxe's upstream MIT license, exact upstream base commit, exact local
  patch, and a machine-readable source record;
- the Haxe Standard Library MIT notice for target override files derived from
  Haxe 4.3.7, plus the complete file-by-file source record at
  `provenance/stdlib-provenance-ledger.json`;
- `release-sbom.json`, a CycloneDX 1.6 inventory of shipped components and the
  Cargo version requirements declared by the shipped `hxrt` crate; and
- `THIRD_PARTY_NOTICES.md`, generated from the same component record as the
  SBOM.

`docs/release-package-components.json` is the editable source for the notice
and SBOM inventory. Required-component license bytes are not editable there:
Haxe and Reflaxe always read their fixed reviewed license files. An additional
component must keep its complete license text inline in this tracked record;
it cannot turn an untracked local file into a release input. Reflaxe's
repository, base, and license facts come from
`vendor/reflaxe/provenance.json`; reflaxe.rust's declared license comes from
`haxelib.json`; and the Haxe version, repository, and reviewed Standard Library
license facts come from `docs/stdlib-provenance-ledger.json`. The license text itself is the
code-owned regular Git file `docs/licenses/haxe-stdlib-4.3.7-MIT.txt`; the ledger cannot redirect
generation to another local path. The generator also checks its recorded SHA-256. Run
`npm run docs:license-artifacts` after changing these inputs. Package and
release checks reject missing or stale copies.

The Reflaxe source record lives at `vendor/reflaxe/provenance.json`. Its normal
check verifies the committed patch digest and changed-file list. When an
upstream checkout is available, this stronger command reconstructs the
vendored tree from the recorded commit:

```sh
node scripts/ci/vendor-reflaxe-provenance.js \
  --upstream-dir /path/to/reflaxe
```

## What the SBOM does not claim

The release ZIP ships `runtime/hxrt/Cargo.toml`, not the source of its crates.
Cargo resolves and downloads those crates when an application is built. The
SBOM therefore records their version requirements as
`declared-not-shipped`; it does not guess the exact version or license selected
by a future application lockfile.

The file-by-file source origin for Haxe standard-library overrides remains in
`docs/stdlib-provenance-ledger.json` in the reviewed source tree. Packaging
copies those exact bytes to `provenance/stdlib-provenance-ledger.json` inside
the ZIP. The release notice points to that package-local record, so an offline
review remains tied to the published artifact rather than to a branch that can
change later.

Release tooling treats these source locations as fixed code-owned inputs. It
rejects symlinks, Git submodules, parent-path references, and alternate local
record pointers. More importantly, the normal and repair workflows extract a
small bootstrap directly from the named Git object with replacement refs and
ambient Git configuration disabled. It materializes literal blobs, then
rechecks every tracked byte after tool installation and before release code is
loaded. Preparation, publication, repair, and artifact verification rebuild
from those named objects rather than live worktree bytes. A standalone
verifier has this authority only inside a repository carrying the matching
external-bootstrap receipt; a live program cannot authenticate its own
pre-execution file. This remains true when ordinary status is fooled by
`assume-unchanged`, `skip-worktree`, checkout filters, line-ending conversion,
replacement refs, or archive attributes. The final package check also
compares the Reflaxe license and
the Haxe/Reflaxe SBOM facts with the exact records inside the archive. This
prevents a clean checkout from publishing bytes that came from an unrelated
file outside the reviewed commit. The SBOM's primary package is selected by the fixed
`reflaxe-rust` component ID rather than editable list order. A separate
Haxelib check requires the installer-facing name and repository to identify
reflaxe.rust and requires a non-empty license; the package verifier then checks
the SBOM's name, kind, license, repository, version, and root dependency identity independently.
The external bootstrap also rejects linked-worktree administration, history
replacement, and tag namespaces that differ from the fetched `origin` tag
snapshot. Only the newly derived stable release tag may appear afterward, and
the reviewed Git command guard publishes that one ref instead of every local
tag. Normal and repair publication verify host controls before mutation and
verify the exact non-prerelease draft plus both approved assets immediately
before making it public. GitHub does not offer one atomic verify-and-publish
operation, so this closes compiler-controlled ordering errors but does not
claim to eliminate an external mutation in the final API-call interval.

## Questions for professional legal review

Before a 1.0 release decision, counsel should answer these concrete questions:

1. Does the repository have the necessary contributor grants to distribute
   reflaxe.rust as `GPL-3.0-only`, and should `haxelib.json` use that exact SPDX
   spelling instead of `GPL-3.0`?
2. Is the included MIT notice and file-by-file origin record sufficient for
   the modified Haxe Standard Library override files, or should each derived
   source file carry an inline notice?
3. Does including the upstream Reflaxe MIT license, exact base, and local patch
   satisfy the desired modified-source notice, or should the package add
   different attribution wording?
4. `hxrt` source is copied into generated Cargo projects. What license and
   user-facing explanation should govern that copied runtime so application
   authors can understand the licensing effect on distributed generated
   programs?
5. Should a compiler release inventory only the Cargo requirements it ships,
   or must release evidence also include one reviewed resolved lockfile with
   the exact licenses of all possible default-feature dependencies?

Until those questions are answered, the artifacts provide reproducible facts
for review, not a legal clearance statement.
