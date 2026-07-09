# Release And SemVer Reference Architecture

This document defines the reusable release architecture that sibling Reflaxe targets and similar
compiler repositories should adapt. It describes invariants and lifecycle boundaries, not a shared
copy-paste script: each repository still owns its package format, version surfaces, and evidence
requirements.

## Why

Release drift is usually an ownership defect. A repository becomes unreliable when package
metadata, public maturity prose, changelog, tags, and downloadable artifacts can each tell a
different story.

A phrase scanner can detect one known disagreement, but it leaves those facts independently owned.
The reference architecture instead makes one structured policy feed deterministic consumers and
verifies each externally visible release boundary.

## Lifecycle

```text
real tag history + next version
              |
              v
structured manifest -> deterministic generator -> prepared release commit
                                                   |
                                                   v
                                        prepared-state verifier
                                                   |
                                                   v
                                                  tag
                                                   |
                                                   v
                                             tag verifier
                                                   |
                                                   v
                                      GitHub Release + artifact
                                                   |
                                                   v
                                        published-state verifier
```

The prepared-state verifier is deliberately after the release commit and before tag creation. That
ordering prevents deterministic metadata, documentation, or artifact failures from leaving a tag
behind. Network and hosting failures can still occur after a tag is pushed, so every adopter also
needs an explicit partial-publication recovery procedure.

## Reference Invariants

1. **Real tags determine version lineage.**
   - Editing metadata never establishes a release by itself.
   - Dry-run evidence must derive the expected next version from reachable tags.
2. **One structured manifest owns release-line policy.**
   - Current and future major-line status/maturity language lives there.
   - Stable generation requires an explicit reviewed approval record.
   - Unknown future majors fail closed.
3. **One generator owns mechanically derivable consumers.**
   - Version metadata, badges, and marker-delimited current-status blocks are rendered together.
   - Check mode renders in memory and compares byte-for-byte without writing.
   - Repeated generation produces byte-identical outputs.
4. **The release workflow derives its commit assets.**
   - Do not repeat the manifest's generated-file inventory in static configuration.
   - Adding a generated consumer automatically adds it to the release commit.
5. **Verification follows the release lifecycle.**
   - Prepared mode checks generated state, changelog, release commit, and packaged artifact before
     tagging.
   - Publish mode checks that the tag contains the same state.
   - Success mode checks the hosted Release, release kind, and exact artifact name.
6. **Current prose is generated or release-line-neutral.**
   - Historical decisions stay dated and preserved.
   - Non-generated pages link to the canonical posture rather than restating a mutable status.
7. **Partial publication is recoverable, not silently skipped.**
   - A tag without its complete hosted Release remains the same failed version.
   - Repair evidence and escalation rules are documented before the failure happens.

## Implementation Map In This Repository

| Responsibility | Owner |
| --- | --- |
| Release-line policy and stable approval | `release-manifest.json` |
| Version and posture rendering | `scripts/release/sync-versions.js` |
| Manifest-derived semantic-release ordering/assets | `release.config.js` |
| Prepared, tag, artifact, and hosted-release checks | `scripts/release/verify-release-state.js` |
| Determinism, failure injection, ordering, and stable-gate contracts | `test/scripts/release-state.test.js` |
| Current posture and graduation criteria | `docs/semver-release-posture.md` |
| Operational workflow and recovery | `docs/release.md` |

## Adoption Sequence For A Sibling Repository

1. Inventory every version field, public current-status statement, changelog owner, package artifact,
   release workflow, and existing tag/release mismatch.
2. Record the actual current line and future stable line in a structured manifest. Do not infer a
   stable claim from old roadmap prose.
3. Add failing contracts for deterministic generation, stale output detection, unapproved stable
   generation, missing tag/artifact, tagged-content drift, and missing hosted assets.
4. Extend the existing version synchronizer into the generator; do not add a parallel posture
   checker.
5. Move mutable current-status prose into generated blocks. Rewrite remaining prose as
   release-line-neutral guidance or explicitly dated history.
6. Derive release-commit assets from the generator and place a non-mutating verifier after the
   release commit but before tag creation.
7. Verify the tag before publication and the hosted Release afterward.
8. Run targeted tests twice, the repository's package/install smoke, a semantic-release dry run, and
   the full relevant application/compiler evidence.
9. Treat the first real release through the new lifecycle as required adoption evidence. A local
   green suite alone does not prove hosting credentials, tag propagation, or asset publication.

## Anti-Patterns

- A standalone scanner that searches several docs for approved phrases.
- A manually repeated generated-file list in semantic-release configuration.
- Stable-major approval represented only by changing a version string.
- Artifact verification that runs only after the tag already exists.
- A successful GitHub Release with an unchecked or ambiguously named package.
- Historical roadmap pages presented as current release truth.
- Calling Git and GitHub publication atomic without a recovery path for external failure.

## Portability Boundary

The architecture is portable; exact files are not. A sibling target should reuse the lifecycle and
invariants while adapting:

- its version surfaces,
- its package builder and artifact inspection,
- its supported distribution hosts,
- its stable-graduation evidence,
- and its application-level pressure test.

Copying repository-specific paths without that audit would recreate synchronization risk under a
different name.
