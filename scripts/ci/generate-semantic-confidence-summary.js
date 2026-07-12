#!/usr/bin/env node
/**
 * Why:
 * `reflaxe.rust` now has enough CI surface that green runs can be overread. This script produces a
 * deterministic evidence rollup that keeps three buckets separate:
 * 1. compile/inventory closure,
 * 2. targeted semantic/runtime parity, and
 * 3. snapshot/smoke-only confidence.
 *
 * What:
 * Generates `docs/semantic-confidence-summary.{json,md}` (or an alternate output directory) from
 * committed repo state and explicit evidence bucket definitions.
 *
 * How:
 * - Reads Tier1/Tier2 sweep lists and the portable stdlib candidate audit.
 * - Discovers semantic-diff / lane-diff / snapshot case counts from the repo.
 * - Validates that every referenced evidence path exists.
 * - Emits stable JSON/Markdown with no timestamps or host-specific data.
 *
 * Usage:
 *   node scripts/ci/generate-semantic-confidence-summary.js --write
 *   node scripts/ci/generate-semantic-confidence-summary.js --check
 *   node scripts/ci/generate-semantic-confidence-summary.js --out-dir .cache/ci-evidence
 */

const cp = require('child_process')
const fs = require('fs')
const path = require('path')

const rootDir = path.resolve(__dirname, '../..')
const defaultOutDir = path.join(rootDir, 'docs')
const defaultJsonRel = 'docs/semantic-confidence-summary.json'
const defaultMdRel = 'docs/semantic-confidence-summary.md'
const tier1Path = path.join(rootDir, 'test/upstream_std_modules.txt')
const tier2Path = path.join(rootDir, 'test/upstream_std_modules_tier2.txt')
const candidateAuditPath = path.join(rootDir, 'docs/portable-stdlib-candidates.json')
const portableSemanticRoot = path.join(rootDir, 'test/semantic_diff')
const laneSemanticRoot = path.join(rootDir, 'test/semantic_diff_lanes')
const snapshotRoot = path.join(rootDir, 'test/snapshot')

function fail(message) {
  console.error(`[semantic-confidence] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const args = {
    mode: 'stdout',
    outDir: defaultOutDir,
    outDirExplicit: false
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--write') {
      if (args.mode !== 'stdout') fail('use only one of --write / --check')
      args.mode = 'write'
      continue
    }
    if (arg === '--check') {
      if (args.mode !== 'stdout') fail('use only one of --write / --check')
      args.mode = 'check'
      continue
    }
    if (arg === '--out-dir') {
      i += 1
      if (i >= argv.length) fail('--out-dir requires a value')
      args.outDir = path.resolve(rootDir, argv[i])
      args.outDirExplicit = true
      continue
    }
    fail(`unknown argument: ${arg}`)
  }

  if (args.mode === 'stdout' && args.outDirExplicit) {
    args.mode = 'write'
  }

  return args
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function parseModuleList(filePath) {
  return fs
    .readFileSync(filePath, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.replace(/#.*/, '').trim())
    .filter((line) => line.length > 0)
}

function listTrackedFiles(rootPath) {
  const rootRel = relativeRepoPath(rootPath)
  try {
    const output = cp.execFileSync('git', ['ls-files', '-z', '--', rootRel], {
      cwd: rootDir,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore']
    })
    return output
      .split('\u0000')
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0)
  } catch (_error) {
    return null
  }
}

function discoverCaseIds(rootPath, options = {}) {
  const requireMainHx = options.requireMainHx === true
  const trackedFiles = listTrackedFiles(rootPath)

  if (trackedFiles != null) {
    const rootRel = `${relativeRepoPath(rootPath)}/`
    const allCaseIds = new Set()
    const caseIdsWithMainHx = new Set()

    for (const trackedFile of trackedFiles) {
      if (!trackedFile.startsWith(rootRel)) {
        continue
      }
      const relative = trackedFile.slice(rootRel.length)
      const parts = relative.split('/')
      if (parts.length < 2) {
        continue
      }
      const caseId = parts[0]
      allCaseIds.add(caseId)
      if (parts.length === 2 && parts[1] === 'Main.hx') {
        caseIdsWithMainHx.add(caseId)
      }
    }

    return uniqueSorted(requireMainHx ? [...caseIdsWithMainHx] : [...allCaseIds])
  }

  if (!fs.existsSync(rootPath)) {
    return []
  }

  return fs
    .readdirSync(rootPath, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .filter((entry) => {
      if (!requireMainHx) {
        return true
      }
      return fs.existsSync(path.join(rootPath, entry.name, 'Main.hx'))
    })
    .map((entry) => entry.name)
    .sort()
}

function uniqueSorted(values) {
  return Array.from(new Set(values)).sort()
}

function relativeRepoPath(value) {
  return path.relative(rootDir, value).split(path.sep).join('/')
}

const bucketDefinitions = [
  {
    id: 'portable-stdlib-inventory',
    class: 'compile_inventory',
    label: 'Portable stdlib inventory closure',
    scope: 'Portable upstream std roots (`Std`, `StringTools`, `Math`, `Date`, `haxe.*`, `sys.*`)',
    evidence: [
      'test/upstream_std_modules.txt',
      'test/upstream_std_modules_tier2.txt',
      'docs/portable-stdlib-candidates.json',
      'scripts/ci/audit-upstream-stdlib-candidates.js'
    ],
    commands: [
      'bash test/run-upstream-stdlib-sweep.sh',
      'bash test/run-upstream-stdlib-sweep.sh --tier tier2',
      'npm run guard:stdlib-candidates',
      'npm run guard:stdlib-candidate-gap'
    ],
    notes: 'Strong inventory and compile/fmt/check closure. Not blanket runtime semantic parity.'
  },
  {
    id: 'family-stdlib-governance-sync',
    class: 'compile_inventory',
    label: 'Family std governance sync',
    scope: 'Local family bootstrap + pin synchronization',
    evidence: [
      'family/family_std_pin.json',
      'test/portable_allowlist.json',
      'test/portable_conformance_tier1.json',
      'tools/family_std_sync.py',
      'family/reflaxe.family.std/tools/verify_family_std.py'
    ],
    commands: ['npm run test:family-stdlib-bootstrap', 'npm run test:family-stdlib-sync'],
    notes: 'Governance and contract sync proof. Not runtime proof by itself.'
  },
  {
    id: 'portable-core-contracts',
    class: 'targeted_semantic_parity',
    label: 'Portable core contract semantics',
    scope: 'Null strings, typed/dynamic exceptions, class/interface subtype-aware catches, generic-base specialization, virtual dispatch, env vars, function-value parity, portable Option/Result',
    evidence: [
      'test/semantic_diff/null_string_concat',
      'test/semantic_diff/exceptions_typed_dynamic',
      'test/semantic_diff/typed_catch_interface',
      'test/semantic_diff/typed_catch_subclass',
      'test/semantic_diff/generic_base_specialization',
      'test/semantic_diff/virtual_dispatch',
      'test/semantic_diff/sys_getenv_null',
      'test/semantic_diff/function_value_mutable_callbacks',
      'test/semantic_diff/closure_capture_mutation',
      'test/semantic_diff/this_method_closure',
      'test/semantic_diff/portable_option_result_basics',
      'test/snapshot/array_shift_nullable_class_return'
    ],
    commands: ['npm run test:semantic-diff', 'bash test/run-snapshots.sh --case array_shift_nullable_class_return'],
    notes: 'These are the current backbone portable semantic fixtures, not a claim about every portable surface.'
  },
  {
    id: 'portable-metal-lane-stability',
    class: 'targeted_semantic_parity',
    label: 'Portable vs `@:rustMetal` lane stability',
    scope: 'Lane-clean programs must keep portable semantics when metal lanes are introduced',
    evidence: ['test/semantic_diff_lanes/lane_clean_arithmetic', 'test/semantic_diff_lanes/lane_clean_dispatch'],
    commands: ['npm run test:semantic-diff:lanes'],
    notes: 'Lane cleanliness is enforced separately; this bucket proves semantic stability for lane-clean programs.'
  },
  {
    id: 'dynamic-reflection-exception-boundaries',
    class: 'targeted_semantic_parity',
    label: 'Dynamic / reflection / exception boundary behavior',
    scope: 'High-risk dynamic receiver, reflection, and thrown Dynamic payload paths',
    evidence: [
      'test/semantic_diff/reflect_dynamic_receivers',
      'test/semantic_diff/exception_dynamic_payload',
      'test/semantic_diff/typed_catch_interface',
      'test/semantic_diff/typed_catch_subclass',
      'test/snapshot/reflect_basic',
      'test/snapshot/reflect_compare_sort',
      'test/snapshot/catch_dynamic'
    ],
    commands: [
      'npm run test:semantic-diff',
      'bash test/run-snapshots.sh --case reflect_basic',
      'bash test/run-snapshots.sh --case reflect_compare_sort',
      'bash test/run-snapshots.sh --case catch_dynamic'
    ],
    notes: 'Targeted proof only. Emitted non-generic class and interface hierarchies now have subtype-aware typed catch parity; exact-type limits remain for generic classes and payloads without emitted subtype metadata.'
  },
  {
    id: 'portable-stdlib-runtime-parity',
    class: 'targeted_semantic_parity',
    label: 'Portable stdlib runtime hotspots',
    scope: 'Bytes, Json replacer, Int64, String substring, and iterator runtime behavior',
    evidence: [
      'test/semantic_diff/bytes_extended_api',
      'test/semantic_diff/json_stringify_replacer',
      'test/semantic_diff/int64_parity',
      'test/semantic_diff/map_key_value_iterator_manual',
      'test/snapshot/string_substring'
    ],
    commands: ['npm run test:semantic-diff', 'bash test/run-snapshots.sh --case string_substring'],
    notes:
      'Focused runtime parity on stdlib families that recently moved from stubs/workarounds to real support. String.substring coverage is snapshot-backed generated Rust plus stdout proof for bounded ASCII and start/end swap behavior.'
  },
  {
    id: 'generic-helper-bound-shape',
    class: 'snapshot_or_smoke_only',
    label: 'Generic helper payload-bound shape',
    scope: 'Generated Rust signatures for method-level generics that mention bounded generated class payloads',
    evidence: ['test/snapshot/generic_helper_payload_bounds', 'test/snapshot/generic_function_type_params'],
    commands: [
      'bash test/run-snapshots.sh --case generic_helper_payload_bounds',
      'bash test/run-snapshots.sh --case generic_function_type_params'
    ],
    notes:
      'Snapshot-backed generated-shape proof. Helper methods returning or reading generated class payloads propagate required class bounds, while unconstrained Option<T> helpers remain bare.'
  },
  {
    id: 'sys-process-failure-paths',
    class: 'targeted_semantic_parity',
    label: 'Process failure / exit behavior',
    scope: 'stdout/stderr/exit-code and kill handling in portable process flows',
    evidence: ['test/semantic_diff/sys_process_failure_paths'],
    commands: ['python3 test/run-semantic-diff.py --case sys_process_failure_paths'],
    notes: 'Targeted parity only. This does not imply blanket cross-platform process semantics.'
  },
  {
    id: 'sys-net-failure-paths',
    class: 'targeted_semantic_parity',
    label: 'Network failure-path behavior',
    scope: 'TCP select/connect-failure behavior on portable socket flows',
    evidence: ['test/semantic_diff/sys_net_failure_paths'],
    commands: ['python3 test/run-semantic-diff.py --case sys_net_failure_paths'],
    notes: 'TCP failure-path parity is covered. UDP and broader platform-specific behavior still sit in the smoke bucket.'
  },
  {
    id: 'sys-http-callback-contract',
    class: 'targeted_semantic_parity',
    label: 'HTTP callback / status / error boundary behavior',
    scope: 'Local-server callback, status, body, and connection-failure behavior for portable `sys.Http`',
    evidence: [
      'test/semantic_diff/sys_http_callback_contract',
      'test/snapshot/sys_http_smoke',
      'test/snapshot/http_base_override_contract'
    ],
    commands: [
      'python3 test/run-semantic-diff.py --case sys_http_callback_contract',
      'bash test/run-snapshots.sh --case sys_http_smoke',
      'bash test/run-snapshots.sh --case http_base_override_contract'
    ],
    notes:
      'Targeted local-server proof for `onStatus(...)`, `onData(...)`, and connection-failure `onError(...)` routing. Multipart/request-assembly confidence still relies on the snapshot/smoke bucket, and this is not blanket host/network semantic parity.'
  },
  {
    id: 'sys-http-snapshot-smoke',
    class: 'snapshot_or_smoke_only',
    label: 'HTTP portable smoke coverage',
    scope: 'Portable HTTP request/response shape and generated Rust behavior',
    evidence: ['test/snapshot/sys_http_smoke', 'test/snapshot/http_base_override_contract'],
    commands: ['bash test/run-snapshots.sh --case sys_http_smoke', 'bash test/run-snapshots.sh --case http_base_override_contract'],
    notes:
      'Snapshot-backed smoke confidence covering multipart/request assembly, duplicate response headers, nullable missing-header lookup, and the HttpBase callback contract. Combine with the targeted semantic `sys_http_callback_contract` fixture for the current honest proof boundary.'
  },
  {
    id: 'sys-ssl-snapshot-smoke',
    class: 'snapshot_or_smoke_only',
    label: 'SSL/TLS snapshot smoke coverage',
    scope: 'SNI certificate selection and generated Rust/runtime shape',
    evidence: ['test/snapshot/sys_ssl_sni'],
    commands: ['bash test/run-snapshots.sh --case sys_ssl_sni'],
    notes: 'Snapshot-backed smoke confidence for the generated/buildable SNI certificate-selection path. Not blanket TLS parity.'
  },
  {
    id: 'rust-async-subset',
    class: 'snapshot_or_smoke_only',
    label: 'Rust-first async subset',
    scope: 'Documented `metal` + `hxrt` async contract (`Async.blockOn`, async helpers, generated-class instance methods)',
    evidence: [
      'test/snapshot/async_entry_boundary',
      'test/snapshot/async_instance_method',
      'test/snapshot/async_retry',
      'test/snapshot/async_select',
      'test/snapshot/rust_async_tasks',
      'examples/async_retry_pipeline',
      'test/negative/async_main_boundary',
      'test/negative/async_constructor_contract',
      'test/negative/async_preview_removed'
    ],
    commands: [
      'bash test/run-snapshots.sh --case async_entry_boundary',
      'bash test/run-snapshots.sh --case async_instance_method',
      'bash test/run-snapshots.sh --case rust_async_tasks',
      'bash scripts/ci/check-metal-policy.sh'
    ],
    notes: 'Backed by dedicated entry-boundary and receiver-shape fixtures plus negative contract guards. This is a stable Rust-first subset, not a blanket async claim across profiles/runtime modes.'
  },
  {
    id: 'sys-thread-eventloop-and-mainloop',
    class: 'snapshot_or_smoke_only',
    label: 'Thread/EventLoop/thread-pool scheduler proof',
    scope: 'Direct `sys.thread.EventLoop`, thread-pool helpers, and narrower MainLoop proof on the Rust target',
    evidence: [
      'test/snapshot/sys_thread_event_loop',
      'test/snapshot/sys_thread_event_loop_repeat_cancel',
      'test/snapshot/sys_thread_deque_basic',
      'test/snapshot/sys_thread_elastic_thread_pool_smoke',
      'test/snapshot/haxe_mainloop_entrypoint_basic',
      'test/snapshot/haxe_mainloop_entrypoint_thread_bridge',
      'examples/sys_thread_smoke',
      'examples/thread_pool_smoke'
    ],
    commands: [
      'bash test/run-snapshots.sh --case sys_thread_event_loop',
      'bash test/run-snapshots.sh --case sys_thread_event_loop_repeat_cancel',
      'bash test/run-snapshots.sh --case sys_thread_deque_basic',
      'bash test/run-snapshots.sh --case sys_thread_elastic_thread_pool_smoke',
      'bash test/run-snapshots.sh --case haxe_mainloop_entrypoint_basic',
      'bash test/run-snapshots.sh --case haxe_mainloop_entrypoint_thread_bridge',
      'bash scripts/ci/windows-smoke.sh',
      'npm run test:all'
    ],
    notes:
      'Direct EventLoop ops now include repeating callback `repeat(...)/cancel(...)` proof, and `Deque`, `FixedThreadPool`, and `ElasticThreadPool` have Rust-target smoke proof. Read `docs/concurrency-posture.md` for the canonical stable/preview/caveat classification. Broader `haxe.MainLoop` / `haxe.EntryPoint` semantics are still not claimed as `--interp`-backed semantic parity.'
  },
  {
    id: 'sys-db-native-environment',
    class: 'snapshot_or_smoke_only',
    label: 'Database/native-environment smoke coverage',
    scope: 'DB bindings that depend on native libraries and destination environment setup',
    evidence: ['test/snapshot/sys_db_mysql_compile', 'test/snapshot/sys_db_sqlite_smoke'],
    commands: [
      'bash test/run-snapshots.sh --case sys_db_mysql_compile',
      'bash test/run-snapshots.sh --case sys_db_sqlite_smoke'
    ],
    notes:
      'SQLite currently has runtime smoke proof via the `:memory:` snapshot, while MySQL is compile-only dependency/codegen coverage. Useful environment-sensitive evidence, not broad runtime parity.'
  },
  {
    id: 'platform-sensitive-windows-smoke',
    class: 'snapshot_or_smoke_only',
    label: 'Platform-sensitive Windows smoke',
    scope: 'Curated sys IO/net/thread scenarios on Windows',
    evidence: ['scripts/ci/windows-smoke.sh', '.github/workflows/ci.yml', '.github/workflows/weekly-ci-evidence.yml'],
    commands: ['bash scripts/ci/windows-smoke.sh'],
    notes: 'Important platform confidence signal. Still a curated smoke subset, not blanket Windows parity.'
  }
]

function buildBuckets() {
  return bucketDefinitions.map((bucket) => {
    for (const relPath of bucket.evidence) {
      const absPath = path.join(rootDir, relPath)
      if (!fs.existsSync(absPath)) {
        fail(`missing evidence path referenced by bucket '${bucket.id}': ${relPath}`)
      }
    }

    return {
      id: bucket.id,
      class: bucket.class,
      label: bucket.label,
      scope: bucket.scope,
      evidence: [...bucket.evidence],
      commands: [...bucket.commands],
      notes: bucket.notes
    }
  })
}

function buildReport() {
  const tier1Modules = uniqueSorted(parseModuleList(tier1Path))
  const tier2Modules = uniqueSorted(parseModuleList(tier2Path))
  const candidateAudit = readJson(candidateAuditPath)
  const portableCases = discoverCaseIds(portableSemanticRoot, { requireMainHx: true })
  const laneCases = discoverCaseIds(laneSemanticRoot, { requireMainHx: true })
  const snapshotCases = discoverCaseIds(snapshotRoot)
  const buckets = buildBuckets()

  const countsByClass = {
    compile_inventory: buckets.filter((bucket) => bucket.class === 'compile_inventory').length,
    targeted_semantic_parity: buckets.filter((bucket) => bucket.class === 'targeted_semantic_parity').length,
    snapshot_or_smoke_only: buckets.filter((bucket) => bucket.class === 'snapshot_or_smoke_only').length
  }

  return {
    schemaVersion: 1,
    contract: 'semantic-confidence-summary',
    description:
      'Deterministic evidence rollup that separates compile/inventory closure, targeted semantic/runtime parity, and snapshot/smoke-only confidence.',
    source: {
      tier1Path: relativeRepoPath(tier1Path),
      tier2Path: relativeRepoPath(tier2Path),
      candidateAuditPath: relativeRepoPath(candidateAuditPath),
      portableSemanticRoot: relativeRepoPath(portableSemanticRoot),
      laneSemanticRoot: relativeRepoPath(laneSemanticRoot),
      snapshotRoot: relativeRepoPath(snapshotRoot)
    },
    counts: {
      tier1SweepModules: tier1Modules.length,
      tier2SweepModules: tier2Modules.length,
      portableCandidateImportableModules: candidateAudit.upstreamImportableModules.length,
      portableCandidateCoveredInTier2: candidateAudit.tier2CoveredModules.length,
      portableCandidateMissingFromTier2: candidateAudit.missingFromTier2.length,
      portableSemanticDiffCases: portableCases.length,
      laneSemanticDiffCases: laneCases.length,
      snapshotCases: snapshotCases.length,
      bucketsByClass: countsByClass
    },
    portableScope: {
      includedRoots: candidateAudit.inScopeRoots,
      excludedTargetNamespacePrefixes: candidateAudit.excludedTargetNamespacePrefixes
    },
    discoveredCases: {
      portableSemanticDiff: portableCases,
      laneSemanticDiff: laneCases
    },
    buckets
  }
}

function stableJson(report) {
  return `${JSON.stringify(report, null, 2)}\n`
}

function renderBucketMd(bucket) {
  const lines = []
  lines.push(`### ${bucket.label}`)
  lines.push(`- Class: \`${bucket.class}\``)
  lines.push(`- Scope: ${bucket.scope}`)
  lines.push(`- Evidence:`)
  for (const relPath of bucket.evidence) {
    lines.push(`  - \`${relPath}\``)
  }
  lines.push(`- Commands:`)
  for (const command of bucket.commands) {
    lines.push(`  - \`${command}\``)
  }
  lines.push(`- Notes: ${bucket.notes}`)
  return lines.join('\n')
}

function renderMarkdown(report) {
  const lines = []
  lines.push('# Semantic Confidence Summary')
  lines.push('')
  lines.push('This file is generated deterministically by `node scripts/ci/generate-semantic-confidence-summary.js --write`.')
  lines.push('')
  lines.push('## Why')
  lines.push('')
  lines.push('Reviewers need a machine-generated answer to a narrow question: what is compile-covered, what is backed by targeted semantic/runtime parity, and what is still only snapshot/smoke confidence?')
  lines.push('')
  lines.push('## What')
  lines.push('')
  lines.push('This summary rolls up the current evidence buckets without pretending that Tier2 inventory closure or a green harness automatically imply blanket runtime parity.')
  lines.push('')
  lines.push('## How')
  lines.push('')
  lines.push('- Reads Tier1/Tier2 module lists and the portable stdlib candidate audit.')
  lines.push('- Discovers semantic-diff / lane-diff / snapshot case counts directly from the repo.')
  lines.push('- Categorizes explicit high-risk buckets with file-backed evidence references.')
  lines.push('- Emits stable JSON/Markdown with no timestamps or machine-local paths.')
  lines.push('')
  lines.push('## Coverage Counts')
  lines.push('')
  lines.push(`- Tier1 sweep modules: \`${report.counts.tier1SweepModules}\``)
  lines.push(`- Tier2 sweep modules: \`${report.counts.tier2SweepModules}\``)
  lines.push(`- Portable candidate importable modules: \`${report.counts.portableCandidateImportableModules}\``)
  lines.push(`- Portable candidate covered in Tier2: \`${report.counts.portableCandidateCoveredInTier2}\``)
  lines.push(`- Portable candidate missing from Tier2: \`${report.counts.portableCandidateMissingFromTier2}\``)
  lines.push(`- Portable semantic-diff cases: \`${report.counts.portableSemanticDiffCases}\``)
  lines.push(`- Lane semantic-diff cases: \`${report.counts.laneSemanticDiffCases}\``)
  lines.push(`- Snapshot cases: \`${report.counts.snapshotCases}\``)
  lines.push(`- Compile/inventory buckets: \`${report.counts.bucketsByClass.compile_inventory}\``)
  lines.push(`- Targeted semantic/runtime buckets: \`${report.counts.bucketsByClass.targeted_semantic_parity}\``)
  lines.push(`- Snapshot/smoke-only buckets: \`${report.counts.bucketsByClass.snapshot_or_smoke_only}\``)
  lines.push('')
  lines.push('## Portable Scope')
  lines.push('')
  lines.push(`- Included roots: ${report.portableScope.includedRoots.map((value) => `\`${value}\``).join(', ')}`)
  lines.push(
    `- Excluded target-specific prefixes: ${report.portableScope.excludedTargetNamespacePrefixes
      .map((value) => `\`${value}\``)
      .join(', ')}`
  )
  lines.push('')
  lines.push('## Compile / Inventory Closure')
  lines.push('')
  for (const bucket of report.buckets.filter((bucket) => bucket.class === 'compile_inventory')) {
    lines.push(renderBucketMd(bucket))
    lines.push('')
  }
  lines.push('## Targeted Semantic / Runtime Parity')
  lines.push('')
  for (const bucket of report.buckets.filter((bucket) => bucket.class === 'targeted_semantic_parity')) {
    lines.push(renderBucketMd(bucket))
    lines.push('')
  }
  lines.push('## Snapshot / Smoke Only')
  lines.push('')
  for (const bucket of report.buckets.filter((bucket) => bucket.class === 'snapshot_or_smoke_only')) {
    lines.push(renderBucketMd(bucket))
    lines.push('')
  }
  lines.push('## Discovered Semantic-Diff Suites')
  lines.push('')
  lines.push(`- Portable semantic-diff cases (${report.discoveredCases.portableSemanticDiff.length}): ${report.discoveredCases.portableSemanticDiff.map((value) => `\`${value}\``).join(', ')}`)
  lines.push(`- Lane semantic-diff cases (${report.discoveredCases.laneSemanticDiff.length}): ${report.discoveredCases.laneSemanticDiff.map((value) => `\`${value}\``).join(', ')}`)
  lines.push('')
  lines.push('## Interpretation Rule')
  lines.push('')
  lines.push('Do not strengthen release/support language from the compile/inventory section alone. Stronger claims require the targeted semantic/runtime section to move with it, or the surface must stay explicitly qualified as snapshot/smoke-only.')
  lines.push('')
  lines.push('For the canonical `sys.Http` / `sys.ssl.*` / `sys.db.*` / platform-sensitive classification, read `docs/systems-environment-posture.md`.')
  lines.push('')
  return `${lines.join('\n')}\n`
}

function writeOutputs(outDir, jsonText, mdText) {
  fs.mkdirSync(outDir, { recursive: true })
  fs.writeFileSync(path.join(outDir, 'semantic-confidence-summary.json'), jsonText)
  fs.writeFileSync(path.join(outDir, 'semantic-confidence-summary.md'), mdText)
}

function checkOutputs(outDir, jsonText, mdText) {
  const jsonPath = path.join(outDir, 'semantic-confidence-summary.json')
  const mdPath = path.join(outDir, 'semantic-confidence-summary.md')
  if (!fs.existsSync(jsonPath) || !fs.existsSync(mdPath)) {
    fail(`missing report artifacts in ${relativeRepoPath(outDir)}. Run: node scripts/ci/generate-semantic-confidence-summary.js --write`)
  }

  const currentJson = fs.readFileSync(jsonPath, 'utf8')
  const currentMd = fs.readFileSync(mdPath, 'utf8')
  if (currentJson !== jsonText || currentMd !== mdText) {
    fail('stale semantic-confidence summary artifacts. Run: node scripts/ci/generate-semantic-confidence-summary.js --write')
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  const report = buildReport()
  const jsonText = stableJson(report)
  const mdText = renderMarkdown(report)

  if (args.mode === 'write') {
    writeOutputs(args.outDir, jsonText, mdText)
    console.log(
      `[semantic-confidence] wrote ${relativeRepoPath(path.join(args.outDir, 'semantic-confidence-summary.json'))} and ${relativeRepoPath(
        path.join(args.outDir, 'semantic-confidence-summary.md')
      )}`
    )
    return
  }

  if (args.mode === 'check') {
    checkOutputs(args.outDir, jsonText, mdText)
    console.log('[semantic-confidence] summary artifacts are current')
    return
  }

  process.stdout.write(jsonText)
}

main()
