# Oracle disposition: fresh Cargo registry authority

## Local baseline

The exact-head haxe.rust harness passed every compiler, runtime, source-map, Rust-floor, and policy stage until the final fresh Cargo check. That check removed the fixture locks, asked the live crates.io index for the newest compatible graph, and required the result to equal tracked bytes. The source commit did not change Cargo requirements, but `num-integer` moved from 0.1.46 to 0.1.47 less than one hour after an earlier evidence refresh. The current script also writes a new baseline directly from a live resolution and then reports `baselineMatched: true`.

The local conclusion before reading Oracle was that repository verification and live registry observation must be separate. Normal verification should consume the reviewed lock. A scheduled or manual observer should propose a new candidate. A separate admission step should consume the reviewed candidate without resolving again.

## Oracle claim matrix

| Oracle claim | Disposition | Local evidence and consequence |
| --- | --- | --- |
| Latest-live equality cannot be a deterministic mandatory gate. | Retained | `runResolutionPass()` removes `Cargo.lock`; `checkBaseline()` then requires byte equality. The two registry-only failures are direct counterexamples. |
| Split the script into `verify-reviewed`, `observe-live`, and `admit`. | Retained | Each mode has one authority: tracked graph, mutable candidate producer, or reviewed candidate admission. This is the smallest design that preserves both stable builds and ecosystem drift visibility. |
| Keep the reviewed 0.1.46 graph out of the current-process feature. | Retained | The feature changed no Cargo manifest. Its three working-tree baseline changes came only from the failed live check and will be removed after the authority repair lands. |
| Require Cargo to be the sibling of the selected rustc for observation and admission. | Retained | The live script enforces exact minimum rustc but currently accepts an unrelated explicit Cargo override. Resolver output is part of admitted evidence. |
| Reject resolution-affecting Cargo/Rust environment overrides. | Retained with a narrow transport exception | Empty `CARGO_HOME` does not neutralize variables such as registry/source config, `RUSTFLAGS`, wrappers, target overrides, or offline mode. Network proxy and certificate transport variables can remain because they do not select semantic package identities. |
| Add truthful mode-specific summary fields. | Retained | The current `baselineMatched: true` claim is false in refresh mode because the candidate was just installed. Each claim will be derived from actions that actually ran. |
| Add a closed dependency-change classifier and fail admission on unknown changes. | Retained | Admission without complete accounting would turn a reviewed candidate directory into a broad file-copy escape. The first classifier will cover every field already present in normalized metadata and Cargo lock evidence. Optional future metadata fields are deferred. |
| Add a non-admissible upper-edge observation using Cargo's incompatible-Rust `allow` mode. | Retained | The floor resolver's fallback mode can hide a newer semver candidate that declares a higher Rust requirement. The upper edge is observation only and can never become the admitted graph. |
| Add an automatic bot PR/update path. | Deferred | Local `observe` and `admit` commands plus a read-only weekly artifact close the current defect. Write authority is a separate decision. |
| Record optional package metadata such as build scripts, proc macros, and feature definitions now. | Deferred | These fields could improve later supply-chain review, but all currently admitted graph fields, versions, sources, checksums, features, topology, and declared MSRV are already in scope. |
| Compiler-server coverage is required. | Rejected as out of scope | The runner consumes existing generated fixture crates and invokes Cargo. It does not change compiler-server state or generation lifecycle. |

## Integrated conclusion

Implement the authority split on a dedicated branch from `adf90b19` before continuing the current-process feature. The mandatory harness and normal CI will verify the exact reviewed graph with frozen Cargo commands. The live registry will be queried only by an explicit local command and a read-only weekly workflow. That command writes a digest-bound candidate and a complete classification. Admission verifies those exact bytes, the observation's base manifest, current policy and fixture inputs, exact minimum toolchain pair, frozen compilation, mutation rejection, and complete change accounting before atomically replacing tracked evidence.

The tracked directory keeps its current path but changes meaning from “latest live” to “reviewed graph.” The existing 0.1.46 graph remains admitted during this repair. The 0.1.47 observation is separate follow-up work and is not needed for the stdio feature.

## Verification and unresolved gaps

This disposition records a validated implementation plan. No repair code or post-repair tests had run when it was written. Required proof is:

- focused policy and script tests, including paired-toolchain, environment, stale base, tampered candidate, unclassified change, checksum incident, removed refresh, offline/frozen, classifier repeatability, and fallback versus upper-edge cases;
- local reviewed verification on exact Rust 1.96 and current stable;
- explicit live observation that reports registry drift without changing tracked files;
- exact-candidate admission dry run or disposable baseline copy test;
- policy guard proof that mandatory jobs never observe live state and the weekly job cannot write repository state;
- complete local haxe.rust harness on one unchanged commit.

Processor: `gpt-5.6-sol`, reasoning level `xhigh`.
