#!/usr/bin/env node

const fs = require('fs')

const allowlistPath = 'docs/portable-stdlib-allowlist.json'
const sweepTier1Path = 'test/upstream_std_modules.txt'
const sweepTier2Path = 'test/upstream_std_modules_tier2.txt'

function fail(msg) {
  console.error(`[ci:guards] ERROR: ${msg}`)
  process.exitCode = 1
}

function parseJson(path) {
  if (!fs.existsSync(path)) {
    fail(`missing file: ${path}`)
    return null
  }
  try {
    return JSON.parse(fs.readFileSync(path, 'utf8'))
  } catch (error) {
    fail(`invalid JSON in ${path}: ${error}`)
    return null
  }
}

function parseModuleList(path) {
  if (!fs.existsSync(path)) {
    fail(`missing module list: ${path}`)
    return []
  }
  const raw = fs.readFileSync(path, 'utf8')
  return raw
    .split(/\r?\n/)
    .map((line) => line.replace(/[ \t]*#.*$/, '').trim())
    .filter((line) => line.length > 0)
}

function summarize(values, limit) {
  const head = values.slice(0, limit).map((value) => `- ${value}`)
  if (values.length > limit) {
    head.push(`- ... (${values.length - limit} more)`)
  }
  return head.join('\n')
}

function duplicates(values) {
  const seen = new Set()
  const out = []
  for (const value of values) {
    if (seen.has(value)) {
      out.push(value)
      continue
    }
    seen.add(value)
  }
  return out
}

function isSorted(values) {
  for (let i = 1; i < values.length; i += 1) {
    if (values[i - 1] > values[i]) {
      return false
    }
  }
  return true
}

const allowlist = parseJson(allowlistPath)
if (allowlist == null || typeof allowlist !== 'object') {
  process.exit(process.exitCode || 1)
}

if (allowlist.schemaVersion !== 1) {
  fail(`${allowlistPath} schemaVersion must be 1`)
}

if (!Array.isArray(allowlist.excludedTargetNamespacePrefixes)) {
  fail(`${allowlistPath} must include excludedTargetNamespacePrefixes array`)
}

if (!Array.isArray(allowlist.tier1UpstreamSweepModules)) {
  fail(`${allowlistPath} must include tier1UpstreamSweepModules array`)
}

const excludedPrefixes = Array.isArray(allowlist.excludedTargetNamespacePrefixes)
  ? allowlist.excludedTargetNamespacePrefixes
  : []
const tier1Modules = Array.isArray(allowlist.tier1UpstreamSweepModules)
  ? allowlist.tier1UpstreamSweepModules
  : []
const sweepTier1Modules = parseModuleList(sweepTier1Path)
const sweepTier2Modules = parseModuleList(sweepTier2Path)

if (duplicates(excludedPrefixes).length > 0) {
  fail(
    `${allowlistPath} has duplicate excluded prefixes:\n${summarize(duplicates(excludedPrefixes), 20)}`
  )
}

if (!isSorted(excludedPrefixes)) {
  fail(`${allowlistPath} excludedTargetNamespacePrefixes must be lexicographically sorted`)
}

function validateModuleSet(modules, label) {
  const dupes = duplicates(modules)
  if (dupes.length > 0) {
    fail(`${label} has duplicate modules:\n${summarize(dupes, 20)}`)
  }
  if (!isSorted(modules)) {
    fail(`${label} must be lexicographically sorted`)
  }
  for (const module of modules) {
    if (typeof module !== 'string' || module.trim().length === 0) {
      fail(`${label} contains an invalid module entry`)
      continue
    }
    for (const prefix of excludedPrefixes) {
      if (module.startsWith(prefix)) {
        fail(`${label} module ${module} uses excluded target namespace prefix ${prefix}`)
        break
      }
    }
  }
}

validateModuleSet(tier1Modules, `${allowlistPath} tier1UpstreamSweepModules`)
validateModuleSet(sweepTier1Modules, sweepTier1Path)
validateModuleSet(sweepTier2Modules, sweepTier2Path)

const tier1Set = new Set(tier1Modules)
const sweepTier1Set = new Set(sweepTier1Modules)
const sweepTier2Set = new Set(sweepTier2Modules)
const missingInSweep = tier1Modules.filter((module) => !sweepTier1Set.has(module))
const extraInSweep = sweepTier1Modules.filter((module) => !tier1Set.has(module))
const tier1MissingInTier2 = tier1Modules.filter((module) => !sweepTier2Set.has(module))

if (missingInSweep.length > 0) {
  fail(
    `Tier1 modules present in ${allowlistPath} but missing in ${sweepTier1Path}:\n${summarize(
      missingInSweep,
      20
    )}`
  )
}

if (extraInSweep.length > 0) {
  fail(
    `Sweep modules present in ${sweepTier1Path} but missing in ${allowlistPath}:\n${summarize(
      extraInSweep,
      20
    )}`
  )
}

if (tier1MissingInTier2.length > 0) {
  fail(
    `Tier1 modules missing from ${sweepTier2Path}:\n${summarize(
      tier1MissingInTier2,
      20
    )}`
  )
}

if (tier1Modules.length !== sweepTier1Modules.length) {
  fail(
    `Tier1 module count mismatch between ${allowlistPath} (${tier1Modules.length}) and ${sweepTier1Path} (${sweepTier1Modules.length})`
  )
}

if (tier1Modules.join('\n') !== sweepTier1Modules.join('\n')) {
  fail(
    `${sweepTier1Path} order differs from ${allowlistPath} tier1UpstreamSweepModules. Keep order deterministic and aligned.`
  )
}

if (process.exitCode) {
  process.exit(process.exitCode)
}

console.log(
  `[ci:guards] OK: portable stdlib allowlist validated (${tier1Modules.length} tier1 modules, ${sweepTier2Modules.length} tier2 modules, ${excludedPrefixes.length} excluded prefixes)`
)
