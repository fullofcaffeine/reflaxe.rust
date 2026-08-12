# Oracle disposition: exact-head Cargo authority review

## Local baseline

The reviewed commit `3a1b6f94` separated mandatory verification, live registry observation, and
explicit admission. Its full local harness passed. A separate fresh-context review then found that
hidden CI evidence would not upload, intentional policy changes could not reach observation, output
paths could traverse symlinks, admission trusted candidate-contained digests, two Rustdoc controls
remained ambient, and two documents overstated the evidence. Those findings were already reproduced
locally before this Oracle answer arrived.

## Oracle claim matrix

| Oracle claim | Disposition | Local evidence and consequence |
| --- | --- | --- |
| Mandatory CI still contains unlocked generated-crate Cargo commands. | Retained | The current-stable job copies generated crates and runs `cargo check` and `cargo clippy` without a reviewed lock. These paths still let registry timing affect a required job. |
| Caller-selected output can traverse an ancestor symlink. | Retained | This matches the independent review. The local repair now rejects symlinked existing path components, but the final design must also avoid destructive replacement through a caller-controlled directory. |
| Cargo configuration and inherited environment are not isolated. | Retained | An isolated `CARGO_HOME` does not stop Cargo from reading ancestor configuration. A broad inherited environment also leaves future semantic inputs unreviewed. |
| Candidate admission is self-authenticating. | Retained and partly repaired | The local repair now requires an operator-recorded SHA-256 over a closed candidate tree and canonical file inventory. Canonical JSON byte checks still need explicit proof. |
| Policy and fixture files can change between observation, verification, and publication. | Retained | The script rereads repository inputs at multiple phases. The final repair needs one immutable input snapshot plus a last repository recheck. |
| Version or source identity changes hide related MSRV, feature, dependency, and graph changes. | Retained | The classifier pairs lock versions but not normalized metadata and resolved nodes across that same logical package update. |
| The two-rename baseline replacement is not crash-atomic. | Retained | A process death after moving the old directory can leave no canonical baseline. Immutable sets plus one small active manifest are the simpler durable design. |
| Execute validated real tool paths instead of mutable symlink spellings. | Retained as bounded hardening | This closes a plausible tool-swap gap without changing the three-mode architecture. |
| One-time replay prevention needs an owner decision. | Deferred | A stale base already rejects ordinary replay. True one-time consumption across a restored identical base is not required for this local reviewed-baseline workflow. |

## Integrated conclusion

Keep the three-mode architecture, but do not open or merge the pull request from `3a1b6f94`.
Complete the retained repairs in the same focused haxe.rust Bead. Mandatory CI must consume reviewed
locks. Cargo must run from an immutable policy-owned input snapshot with a small allowlisted
environment and no unreviewed ancestor configuration. The candidate must have canonical bytes and
an externally supplied reviewed digest. Classification must compare the complete normalized package
and graph relation across version and source moves. Baseline publication must use immutable content
plus one crash-atomic selector, or an equally strong transaction and recovery design.

The existing local fixes for hidden-file uploads, intentional policy-change observation, candidate
tree binding, symlink rejection, clean-checkout tests, Rustdoc controls, and documentation remain
valid. They require another exact-head full harness and exact-head Oracle review after the remaining
repairs.

## Verification and unresolved gaps

Tests actually run on the uncommitted first repair include the focused policy suite, policy guard,
workflow test, clean-artifact test, generated-report contract, architecture and scorecard guards,
documentation checks, reviewed Rust 1.96 Cargo verification, live two-pass observation, and exact
digest-bound admission dry run. The full harness result belongs only to `3a1b6f94`; it does not yet
cover the current repair. Hosted Linux and Windows evidence, immutable input races, hierarchical
Cargo configuration, complete cross-version classification, and crash-safe baseline selection remain
to be implemented and tested.

Oracle reviewer: GPT-5.6 Pro. Local disposition processor: `gpt-5.6-sol`, reasoning level `xhigh`.
