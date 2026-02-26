#!/usr/bin/env node

const cp = require('child_process')
const fs = require('fs')

function fail(msg) {
  console.error(`[ci:guards] ERROR: ${msg}`)
  process.exitCode = 1
}

function gitTrackedUnder(path) {
  try {
    const out = cp.execFileSync('git', ['ls-files', '-z', '--', path], { encoding: 'utf8' })
    return out.split('\0').filter(Boolean)
  } catch (_) {
    return []
  }
}

function summarize(paths, limit) {
  const slice = paths.slice(0, limit).map((path) => `- ${path}`)
  const suffix = paths.length > limit ? `\n- ... (${paths.length - limit} more)` : ''
  return `${slice.join('\n')}${suffix}`
}

const ledgerPath = 'docs/stdlib-provenance-ledger.json'
const stdRoot = 'std/'
const tier2ModulesPath = 'test/upstream_std_modules_tier2.txt'

function parseModuleList(path) {
  if (!fs.existsSync(path)) {
    fail(`missing module list: ${path}`)
    return []
  }
  return fs
    .readFileSync(path, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.replace(/[ \t]*#.*$/, '').trim())
    .filter((line) => line.length > 0)
}

function ledgerPathToModule(path) {
  if (!path.startsWith(stdRoot) || !path.endsWith('.cross.hx')) {
    return null
  }
  const moduleName = path
    .slice(stdRoot.length, -'.cross.hx'.length)
    .replace(/\//g, '.')
  return moduleName.length > 0 ? moduleName : null
}

if (!fs.existsSync(ledgerPath)) {
  fail(`missing stdlib provenance ledger: ${ledgerPath}`)
  process.exit(process.exitCode)
}

let ledger = null
try {
  ledger = JSON.parse(fs.readFileSync(ledgerPath, 'utf8'))
} catch (error) {
  fail(`invalid JSON in ${ledgerPath}: ${error}`)
  process.exit(process.exitCode)
}

if (ledger == null || typeof ledger !== 'object') {
  fail(`${ledgerPath} must contain a JSON object`)
}

if (!Array.isArray(ledger.entries)) {
  fail(`${ledgerPath} must contain an entries array`)
}

const trackedStdCrossFiles = gitTrackedUnder('std').filter(
  (path) => path.startsWith(stdRoot) && path.endsWith('.cross.hx')
)
const trackedSet = new Set(trackedStdCrossFiles)
const tier2Modules = parseModuleList(tier2ModulesPath)
const tier2Set = new Set(tier2Modules)

const ledgerPaths = []
const expectedTier2Modules = []
const tier2Excluded = []
for (const entry of ledger.entries) {
  if (entry == null || typeof entry !== 'object') {
    fail(`${ledgerPath} contains a non-object entry`)
    continue
  }

  const path = entry.path
  const provenanceKind = entry.provenanceKind
  const upstreamOraclePath = entry.upstreamOraclePath
  const tier2SweepExcludeReason = entry.tier2SweepExcludeReason

  if (typeof path !== 'string' || path.length === 0) {
    fail(`${ledgerPath} entry is missing path`)
    continue
  }

  if (!path.startsWith(stdRoot)) {
    fail(`${ledgerPath} entry path must stay under ${stdRoot}: ${path}`)
  }

  if (!path.endsWith('.cross.hx')) {
    fail(`${ledgerPath} entry path must target a .cross.hx file: ${path}`)
  }

  if (ledgerPaths.includes(path)) {
    fail(`${ledgerPath} contains duplicate path entry: ${path}`)
  }
  ledgerPaths.push(path)

  if (
    provenanceKind !== 'upstream_std_sync' &&
    provenanceKind !== 'repo_authored_override'
  ) {
    fail(
      `${ledgerPath} entry provenanceKind must be upstream_std_sync or repo_authored_override for ${path}`
    )
  }

  if (provenanceKind === 'upstream_std_sync') {
    if (typeof upstreamOraclePath !== 'string' || upstreamOraclePath.length === 0) {
      fail(`${ledgerPath} entry is missing upstreamOraclePath for ${path}`)
    } else if (!upstreamOraclePath.startsWith('vendor/haxe/std/')) {
      fail(
        `${ledgerPath} entry upstreamOraclePath must point to vendor/haxe/std/** for ${path}: ${upstreamOraclePath}`
      )
    }
  }

  if (
    tier2SweepExcludeReason != null &&
    (typeof tier2SweepExcludeReason !== 'string' || tier2SweepExcludeReason.trim().length === 0)
  ) {
    fail(`${ledgerPath} tier2SweepExcludeReason must be a non-empty string for ${path}`)
  }

  const moduleName = ledgerPathToModule(path)
  if (moduleName == null) {
    if (tier2SweepExcludeReason == null) {
      fail(
        `${ledgerPath} entry cannot derive a Tier2 module from ${path}; add tier2SweepExcludeReason`
      )
    } else {
      tier2Excluded.push(`${path} (${tier2SweepExcludeReason})`)
    }
    continue
  }

  if (tier2SweepExcludeReason != null) {
    tier2Excluded.push(`${moduleName} (${tier2SweepExcludeReason})`)
    continue
  }

  expectedTier2Modules.push(moduleName)
}

const ledgerSet = new Set(ledgerPaths)
const missingCoverage = trackedStdCrossFiles.filter((path) => !ledgerSet.has(path))
const staleCoverage = ledgerPaths.filter((path) => !trackedSet.has(path))
const uniqueExpectedTier2Modules = Array.from(new Set(expectedTier2Modules)).sort()
const missingTier2Coverage = uniqueExpectedTier2Modules.filter((moduleName) => !tier2Set.has(moduleName))

if (missingCoverage.length > 0) {
  fail(
    `stdlib provenance ledger missing tracked .cross.hx files:\n${summarize(missingCoverage, 20)}`
  )
}

if (staleCoverage.length > 0) {
  fail(
    `stdlib provenance ledger references non-tracked .cross.hx files:\n${summarize(staleCoverage, 20)}`
  )
}

if (missingTier2Coverage.length > 0) {
  fail(
    `Tier2 upstream sweep is missing modules derived from ${ledgerPath} entries:\n${summarize(
      missingTier2Coverage,
      20
    )}`
  )
}

if (process.exitCode) process.exit(process.exitCode)
console.log(
  `[ci:guards] OK: stdlib provenance ledger covers ${trackedStdCrossFiles.length} tracked .cross.hx files and ${uniqueExpectedTier2Modules.length} ledger-derived Tier2 modules (${tier2Excluded.length} explicit Tier2 exclusions)`
)
