# Testing Strategy and Product-Surface Scorecards

> Generated from `docs/testing-surface-scorecards.json`. Run `npm run docs:sync:testing-scorecards` after reviewing the structured source.

This page says what each test group can actually prove. A green result for one row does not make a different row green.

## Incremental strategy audit

| New conclusion | Current state | Concrete evidence or limit |
| --- | --- | --- |
| behavior scenarios before broad automation | partial | Beads acceptance criteria and .audit decision trails capture real recent scenarios; the required scenario fields are now documented for future behavior work. |
| red test at the lowest faithful layer | satisfied | AGENTS.md requires contract-first testing, and the representative workflow below records the actual pre-fix failure command and reason. |
| independent source for expected results | partial | Portable semantic comparisons use Haxe --interp, important generated shapes use reviewed contracts, and snapshots require review. Older fixtures do not all carry an explicit expected-result note. |
| one vertical tracer bullet before permutations | satisfied | The immutable rust.Ref<T> to Dynamic route is checked from typed Haxe analysis through generated Rust, Cargo, and runtime output before its negative permutation matrix. |
| focused regression plus real-boundary proof | satisfied | Representation, runtime, source-map, semantic-diff, package, example, Windows, and consumer lanes combine focused owners with real Cargo or system observers. |
| surface-specific portfolio review | partial | The scorecards below separate claims, but complete unique-owner ratios and failure-yield measurements remain report-only follow-up work. |
| examples execute at the level they advertise | satisfied | Every tracked example is classified below; CI compiles authored Haxe and runs Cargo tests and the generated program for the claim-bearing matrix. |
| R0-R5 feedback rings with safe affected selection | partial | Focused, hook, PR, extended, weekly, and release paths exist. Semantic-owner affected selection is not yet allowed to remove PR checks; haxe.rust-oo3.101 owns observation mode first. |
| separate high-risk review pass | satisfied | thinking:xhigh work requires a second pass, normally an exact-commit Oracle review, and the checklist below challenges test sensitivity and claim boundaries. |

## Independent product surfaces

| Surface | Status | Official Haxe qualification | Focused owners | Real vertical owners | Full backstop |
| --- | --- | --- | ---: | ---: | --- |
| Portable regular-Haxe compiler behavior | partial | applies | 2 | 2 | `npm run test:all` |
| Representation, lowering, ownership, borrowing, traits, and metal | partial | does-not-apply | 2 | 2 | `npm run test:all` |
| Runtime-backed Haxe behavior | partial | does-not-apply | 2 | 2 | `npm run test:all` |
| No-hxrt eligibility and emitted dependency absence | partial | does-not-apply | 2 | 2 | `npm run test:all` |
| Diagnostics and deterministic source mapping | partial | does-not-apply | 2 | 2 | `npm run test:all` |
| Cargo, package, downstream, release, and platform behavior | partial | does-not-apply | 2 | 2 | `npm run ci:local` |

### Portable regular-Haxe compiler behavior

**Claims protected**

- Supported regular Haxe programs preserve the reviewed Haxe behavior when compiled to Rust.
- Portable standard-library inventory coverage is not presented as blanket runtime parity.

**Focused owners**

- `npm run test:semantic-diff` — test/semantic_diff
- `npm run test:rust-structural-items` — test/compiler

**Real vertical owners**

- `npm run test:semantic-diff` — Haxe --interp compared with generated Rust run
- `npm run test:upstream-stdlib` — generated Cargo check across the Tier1 portable module inventory

**Downstream or platform owners**

- `npm run test:windows-smoke` — Windows runner

Last clean proof: .audit/haxe-rust-oo3.98.3.2-oracle-c1c95fbe.tsv row 65.

**Remaining limits**

- A pinned official Haxe target-qualification checkout is not yet integrated; haxe.rust-oo3.102 owns that bounded smoke.

### Representation, lowering, ownership, borrowing, traits, and metal

**Claims protected**

- Typed representation and borrow decisions agree with emitted Rust ownership behavior.
- Rust-native metal routes remain separate from portable Haxe compatibility claims.

**Focused owners**

- `npm run test:rust-representation-plan` — test/scripts/rust-representation-plan.test.js
- `npm run test:rust-structural-pass-analysis` — test/compiler

**Real vertical owners**

- `npm run test:rust-representation-plan` — saved decision audit, generated Rust shape, Cargo check, and runtime stdout
- `npm test` — generated Rust, rustfmt, Cargo build, and reviewed output

**Downstream or platform owners**

- `npm run test:codex-hxrust` — independent consumer application

Last clean proof: .audit/haxe-rust-oo3.98.3.2-oracle-c1c95fbe.tsv rows 63-65.

**Remaining limits**

- The broad architecture-capability epic remains open; this scorecard covers only named admitted routes.

### Runtime-backed Haxe behavior

**Claims protected**

- Runtime helpers are used only where runtime state or Haxe behavior requires them.
- Identity, lifecycle, exception, reflection, thread, and platform behavior is proved at a real runtime boundary.

**Focused owners**

- `npm run test:hxref-lifecycle` — runtime/hxrt
- `npm run test:runtime-e2e-contract` — test/runtime_e2e

**Real vertical owners**

- `npm run test:runtime-e2e-contract` — isolated generated target processes
- `npm run test:semantic-diff` — Haxe and generated Rust runtime comparison

**Downstream or platform owners**

- `npm run test:windows-smoke` — Windows platform behavior

Last clean proof: .audit/haxe-rust-oo3.98.3.2-oracle-c1c95fbe.tsv row 65.

**Remaining limits**

- Green runtime checks do not advance no-hxrt claims.

### No-hxrt eligibility and emitted dependency absence

**Claims protected**

- Eligible programs emit and build without hxrt.
- Ineligible source fails at the exact Haxe boundary before a late generated-Rust backstop becomes the normal detector.

**Focused owners**

- `npm run test:rust-representation-plan` — test/negative/representation_dynamic_crossings
- `npm run test:metal-fallback` — scripts/ci/check-metal-policy.sh

**Real vertical owners**

- `bash scripts/ci/check-metal-policy.sh` — cold generated crate inspection and Cargo build
- `HARNESS_STAGES=examples bash scripts/ci/harness.sh` — generated no-hxrt TCP/UDP runtime

Last clean proof: .audit/haxe-rust-oo3.98.3.2-oracle-c1c95fbe.tsv row 65.

**Remaining limits**

- Warm compiler state is never accepted as release proof for dependency absence; exact-profile cold generation remains required.

### Diagnostics and deterministic source mapping

**Claims protected**

- Errors point to the exact stable Haxe location without leaking machine paths.
- Source maps and reports are deterministic in UTF-8 byte coordinates.

**Focused owners**

- `npm run test:rust-source-map` — test/scripts/rust-source-map.test.js
- `npm run test:diagnostic-contract` — test/scripts/diagnostic-contract.test.js

**Real vertical owners**

- `npm run test:diagnostic-contract:runtime` — real compiler diagnostics from authored Haxe
- `npm run test:rust-source-map` — generated Rust map plus exact original content

Last clean proof: .audit/haxe-rust-oo3.98.3.2-oracle-c1c95fbe.tsv row 65.

**Remaining limits**

- Broader transformed-origin coverage remains tracked separately from the exact boundaries already admitted.

### Cargo, package, downstream, release, and platform behavior

**Claims protected**

- Generated Cargo projects build with the supported Rust policy and reviewed dependency graph.
- The release package is rebuilt from reviewed inputs and verified independently of the candidate archive.
- Downstream and platform checks stay separate from compiler semantic claims.

**Focused owners**

- `npm run test:release-artifact` — test/scripts/release-artifact.test.js
- `npm run test:rust-toolchain-policy` — test/scripts/rust-toolchain-policy.test.js

**Real vertical owners**

- `npm run test:package-smoke` — clean Haxelib install, Haxe compile, Cargo build, and run
- `npm run test:fresh-cargo-resolution` — empty Cargo homes on the exact minimum toolchain

**Downstream or platform owners**

- `npm run test:codex-hxrust` — independent application
- `npm run test:windows-smoke` — Windows runner

Last clean proof: .audit/haxe-rust-p6hs.13.tsv rows 28-29.

**Remaining limits**

- Professional legal approval is separate from engineering release-integrity checks.

## Feedback rings

| Ring | Purpose | Current command/owner | Selection | Cache rule |
| --- | --- | --- | --- | --- |
| R0 | focused owner | npm run test:rust-representation-plan (or the named smallest owner) | manual exact command | Warm reuse is allowed for iteration, but not for no-hxrt or release proof. |
| R1 | local smoke and pre-commit | installed scripts/hooks/pre-commit plus npm run hooks:check | path triggers with fail-closed freshness checks | Developer caches are allowed; generated evidence must remain byte-identical. |
| R2 | required pull request | .github/workflows/ci.yml harness and policy jobs | broad required shards; no semantic test is removed by an affected selector | Tool downloads may be cached; product outputs are regenerated. |
| R3 | extended | npm run test:upstream-stdlib:tier2 plus PR performance and platform jobs | currently broad rather than affected; observation-mode semantic selection is deferred to haxe.rust-oo3.101 | Selector misses cannot hide because the broad job remains active. |
| R4 | full and weekly | npm run ci:local and .github/workflows/weekly-ci-evidence.yml | always-run backstop | Caches may speed tools; immutable reports and clean generated outputs remain separate. |
| R5 | release | .github/workflows/ci.yml release job and npm run test:release | release policy only; never affected-path selection | Cold exact-profile proof is required; a warm compiler cache cannot prove no-hxrt or release behavior. |

## Examples and the level they prove

| Example | Tier | Product surfaces | Actually observed in CI |
| --- | --- | --- | --- |
| `examples/async_retry_pipeline` | capability-showcase | representation-metal, runtime | authored-haxe, compile, cargo-build, cargo-test, runtime |
| `examples/bytes_ops` | capability-showcase | portable-compiler, runtime | authored-haxe, compile, cargo-build, cargo-test, runtime |
| `examples/chat_loopback` | flagship-application | portable-compiler, representation-metal, runtime, cargo-package-platform | authored-haxe, compile, cargo-build, cargo-test, runtime |
| `examples/classes` | compile-only-snippet | portable-compiler | authored-haxe, compile, cargo-build, runtime |
| `examples/hello` | capability-showcase | portable-compiler, cargo-package-platform | authored-haxe, compile, cargo-build, runtime |
| `examples/metal_first_dataflow` | capability-showcase | representation-metal | authored-haxe, compile, cargo-build, cargo-test, runtime |
| `examples/metal_native_net` | capability-showcase | representation-metal, no-hxrt | authored-haxe, compile, cargo-build, runtime |
| `examples/profile_storyboard` | capability-showcase | portable-compiler, representation-metal, cargo-package-platform | authored-haxe, compile, cargo-build, cargo-test, runtime, native-differential |
| `examples/serde_json` | capability-showcase | portable-compiler, runtime | authored-haxe, compile, cargo-build, cargo-test, runtime |
| `examples/sys_file_io` | capability-showcase | portable-compiler, runtime | authored-haxe, compile, cargo-build, runtime, platform |
| `examples/sys_net_loopback` | capability-showcase | portable-compiler, runtime | authored-haxe, compile, cargo-build, runtime, platform |
| `examples/sys_process` | capability-showcase | portable-compiler, runtime | authored-haxe, compile, cargo-build, runtime, platform |
| `examples/sys_thread_smoke` | capability-showcase | portable-compiler, runtime | authored-haxe, compile, cargo-build, runtime, platform |
| `examples/thread_pool_smoke` | capability-showcase | portable-compiler, runtime | authored-haxe, compile, cargo-build, runtime |
| `examples/tui_todo` | flagship-application | portable-compiler, runtime | authored-haxe, compile, cargo-build, cargo-test, runtime |

## Representative behavior-first workflow

### Scoped Rust borrow hidden inside a runtime anonymous record

Product surface: `representation-metal`.

- Preconditions: A typed anonymous record declares an optional field whose transparent Haxe type ultimately contains a scoped Rust borrow.
- Action: Compile a runtime-name reflection write and typed read through the representation-plan fixture.
- Observable result: Compilation reports HXRS-BORROW-REGION at the Haxe value before any Rust source directory is created.
- Edge behavior: Deep acyclic wrappers and abstracts around the whole record are rejected, while equally deep owned values and recursive owned records remain accepted.
- Protected claim: Runtime anonymous records cannot store an owned value under a field later exposed as a scoped Rust borrow.

**Red state before the fix**

- Command: `npm run test:rust-representation-plan`
- Failure: The deep wrapper, outer-record abstract, and omitted mutable-borrow field compiled past the intended early check.
- Durable record: .audit/haxe-rust-oo3.98.3.2-oracle-c1c95fbe.tsv row 63.

**Source of the expected result**

- Kind: manually-authored-invariant.
- Source: Haxe transparent-type meaning plus the reviewed Rust Anon::get<T> owned-value and lifetime contract.
- Independence: The expectation comes from the source-language type and Rust lifetime rules, not from reusing the emitter's classification algorithm.

**First real vertical path**

- Fixture: `test/positive/representation_borrow_dynamic`
- Command: `npm run test:rust-representation-plan`
- Observed levels: authored-haxe -> typed-decision -> generated-rust -> cargo-build -> runtime.
- Result: The saved decision is consumed once, generated Rust copies or clones the owned referent, Cargo accepts it, and runtime prints 7|hello|true without a borrow escaping.

**Broader proof**

- Command: `npm run test:all`
- Result: Passed in 7201 seconds across 138 snapshots, 36 portable behavior comparisons, runtime, package, examples, and policy gates.
- Durable record: .audit/haxe-rust-oo3.98.3.2-oracle-c1c95fbe.tsv row 65.

## Expected-result and review rules

Expected results must come from a specification, a manually written minimal expectation, a pinned comparison implementation, an invariant, a reviewed generated file, or real consumer behavior. The emitter must not generate its own expected answer.

For representation, runtime, ABI, package, security, migration, source-location, or public-claim changes, a review pass separate from implementation must answer:

- Did the new or changed test fail for the intended reason before the fix?
- Is the expected result independent of the implementation being tested?
- Are important negative and edge cases missing?
- Does a mock remove the boundary named by the claim?
- Could path-based selection skip the real semantic owner?
- Is a green result from one product surface being used to advance another surface?
- Does the public wording claim more than the observed compile, build, runtime, package, or platform level?

## Retries and quarantine

- Product test retries: disabled.
- Network retries: allowed only around external downloads and must not hide a product-test failure.
- Quarantine: A claim-bearing test may be quarantined only with an owner, expiry, Bead, preserved failure artifact, and another active proof for the same public claim.
- Current quarantines: 0.

## Portfolio interpretation

Review each product surface separately. These are planning ranges, not quotas, and static policy checks are outside the denominator.

The repository has strong focused and vertical owners, but it does not yet publish a complete unique-owner count per surface. haxe.rust-oo3.101 tracks report-only measurement and affected-test observation.
