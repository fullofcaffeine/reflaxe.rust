# Release And SemVer Reference Architecture

This is the small release protocol sibling Reflaxe targets and similar repositories should adapt.
SemVer remains responsible for version meaning; the protocol adds the minimum integrity needed to
bind a tested source commit to an immutable hosted artifact.

## Reference Flow

```text
required CI succeeds for commit S
              |
              v
derive V from real tags + changes + release-line policy
              |
              v
build and fully validate deterministic artifact A from S
              |
              v
create immutable tag vV at S
              |
              v
publish A + checksum and verify hosted SHA-256
```

There is no commit created inside publication. If exact versions must remain committed for a
different ecosystem, use the optional release-PR extension described below so ordinary CI tests the
versioned commit before it is tagged.

## Universal Invariants

1. **Real tags own exact version lineage.**
   - Generated package metadata never selects or blocks the next version.
   - A standard, locked SemVer implementation parses versions.
2. **Release-line policy stays small and explicit.**
   - Initial-development breaking-bump behavior is deliberate.
   - Every stable major owns an independent reviewed approval; unknown majors fail closed.
3. **Publication uses the exact tested commit.**
   - The release job is downstream of required jobs in the same trusted push workflow.
   - The checked-out HEAD, local tag, and remote tag all resolve to that CI SHA.
4. **One project adapter owns artifact production.**
   - Exact release metadata is injected into staging, never written back to the checkout.
   - The tracked tree remains unchanged.
5. **The artifact is reproducible and fully inspected.**
   - Complete builds in different environments produce byte-identical output.
   - Layout, entry safety, required content, metadata, and the real install/use smoke apply to the
     exact bytes that will be uploaded.
6. **Hosted bytes equal approved bytes.**
   - A checksum sidecar names the versioned artifact.
   - Hosted state, length, and digest match local approved files; unexpected assets fail.
7. **Version tags and published releases are immutable.**
   - A remote version tag is never moved or deleted.
   - Invalid public content requires a corrective version.
8. **Repair finishes the same version.**
   - Manual repair accepts only an existing tag and cannot analyze commits or create a version.
   - It completes an absent/draft hosted release, or verifies an already immutable one.
9. **Normal no-op commits remain no-op.**
   - Release automation runs after successful main CI and lets semantic-release decide there is no
     relevant change; commit-message phrase filters are unnecessary.
10. **Documentation states durable policy.**
    - The latest release/tag supplies patch-version truth.
    - Policy pages do not need a release-time rewrite.

## Core Versus Repository Adapter

| Universal core | Repository-specific adapter |
| --- | --- |
| Strict SemVer parser | Package metadata/layout |
| Conventional Commit analysis | Artifact filename/labels |
| `0.x` and stable-major policy | Deterministic package builder |
| Same-SHA CI/release gate | Required archive contents |
| Local/remote tag identity | Install/compiler/application smoke |
| Hosted size/digest verification | Distribution-host details |
| Immutable tag/release policy | Toolchain needed to build the artifact |
| Existing-tag repair state machine | Product-specific readiness evidence |

Copy the left column. Reimplement and test the right column for each repository.

## haxe.rust Implementation Map

| Responsibility | Owner |
| --- | --- |
| Release-line policy | `release-manifest.json` |
| Strict policy helpers | `scripts/release/release-policy.js` |
| Conventional Commit policy adapter | `scripts/release/semantic-release-policy.cjs` |
| Haxelib staging | `scripts/release/prepare-package-metadata.js` |
| Deterministic ZIP | `scripts/release/deterministic-zip.js` |
| Full archive contract | `scripts/release/verify-release-artifact.js` |
| Artifact production and pre-host tag check | `scripts/release/haxelib-artifact-plugin.cjs` |
| Tag/hosted digest identity | `scripts/release/release-provenance.js` |
| Post-host verification | `scripts/release/published-verifier-plugin.cjs` |
| Same-SHA normal publication | `.github/workflows/ci.yml` |
| Existing-tag repair only | `.github/workflows/release-repair.yml` |
| Focused regression suite | `test/scripts/release-*.test.js` |

## Optional Extension: Committed Version Files

Some ecosystems genuinely require exact versions or changelogs in the source tree. Do not recreate
a release commit inside publication. Use:

```text
derive candidate version -> open/update release PR -> normal CI -> merge -> tag tested merge
```

The PR makes version mutation reviewable and ensures the tagged commit is the commit CI tested.
This extension is optional; repositories whose artifacts can receive staged metadata should keep
the smaller default protocol.

## Adoption Sequence

1. Inventory actual package artifacts and decide whether committed versions are truly required.
2. Preserve real tag history; remove package-metadata ownership of release lineage.
3. Add strict SemVer and explicit initial-development/stable-major policy tests.
4. Put normal publication behind required jobs for the exact trusted default-branch SHA.
5. Build one fixed local artifact path and inject the version only in staging.
6. Make the full package reproducible and validate the exact artifact with its real consumer smoke.
7. Bind checked-out commit, local/remote tag, staged metadata, checksum, and hosted digest.
8. Enable host immutability and version-tag update/deletion protection.
9. If no version history exists, establish a reviewed `v0.0.0` major-zero baseline before enabling
   automation; semantic-release otherwise treats its first release as `1.0.0`.
10. Add an existing-tag repair path that cannot derive or create a version.
11. Prove one real release and a subsequent no-op commit before claiming adoption complete.

## Evidence

`v0.81.3` is dated predecessor evidence: it proved one happy-path execution of the former
release-commit design (implementation `a27f7254`, release commit/tag `f9b9ac15`, CI `29053967075`,
Release run `29054963288`, archive SHA-256
`8fef7a08e306f92a519d397cb650da756c50ba6e1a1928d69311726b2c46f536`, and no-op follow-up
`29056092503`). It did not prove all failure paths and motivated the simplification.

`v0.81.4` is the first live proof of the smaller protocol. CI run `29107200668` passed every
required job for source commit `341f9af0`, and its final release job tagged that exact commit without
creating another commit. The deterministic Haxelib artifact is 662,266 bytes with SHA-256
`531442c997dbaec734882844eb23dce5cd726eae673c489f13a9a2b5ebe31715`; the hosted checksum asset
has SHA-256 `5c16b793153ec194a0ce1204faf6cab2e7ee2aed63de8364689b768b085f2b0c`.
Independent verification resolved local tag, remote tag, and HEAD to the same commit, downloaded
and hashed the ZIP, matched its sidecar, confirmed the exact two-asset set, and confirmed the
GitHub Release is published, non-prerelease, and immutable. The tag still contains development
sentinels (`package.json` `0.0.0-development`, `haxelib.json` `0.0.0`), proving tracked metadata did
not participate in version lineage. Docs-only follow-up commit `a6f1defd` then passed full CI run
`29109083126`; its release job found `v0.81.4`, analyzed that one docs commit, produced a clean
no-op, created no `v0.81.5` tag, and left `v0.81.4` as the latest Release.

## Anti-Patterns

- Creating and pushing a new release commit after CI tested another commit.
- Letting tracked package versions influence tag-derived version analysis.
- Custom SemVer regexes where a standards-tested library exists.
- Rewriting current prose and badges on every patch release.
- Treating a same-name hosted asset as byte identity.
- Running normal publication from manual branch/SHA input.
- Moving a remote version tag to repair bad publication.
- Copying haxe.rust's Haxelib adapter into a non-Haxelib repository.
