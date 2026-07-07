#!/usr/bin/env node

const cp = require('child_process')
const fs = require('fs')

const manifestPath = 'docs/native-facade-manifest.json'
const helperRoot = 'std/rust/native'
const allowedClassifications = new Set([
  'permanent-native-facade',
  'lowering-candidate',
  'experimental-scaffold'
])
const allowedRuntimeContracts = new Set(['no-hxrt', 'hxrt-bridge'])

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
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

function summarize(values, limit) {
  const slice = values.slice(0, limit).map((value) => `- ${value}`)
  const suffix = values.length > limit ? `\n- ... (${values.length - limit} more)` : ''
  return `${slice.join('\n')}${suffix}`
}

function stripRustComments(source) {
  let output = ''
  let blockDepth = 0
  let inString = false
  let stringQuote = ''
  let escaped = false

  for (let index = 0; index < source.length; index += 1) {
    const ch = source[index]
    const next = source[index + 1] || ''

    if (blockDepth > 0) {
      if (ch === '/' && next === '*') {
        blockDepth += 1
        index += 1
      } else if (ch === '*' && next === '/') {
        blockDepth -= 1
        index += 1
      } else if (ch === '\n') {
        output += '\n'
      }
      continue
    }

    if (inString) {
      output += ch
      if (escaped) {
        escaped = false
      } else if (ch === '\\') {
        escaped = true
      } else if (ch === stringQuote) {
        inString = false
        stringQuote = ''
      }
      continue
    }

    if ((ch === '"' || ch === "'") && !isRustLifetimeQuote(source, index)) {
      inString = true
      stringQuote = ch
      output += ch
      continue
    }

    if (ch === '/' && next === '/') {
      while (index < source.length && source[index] !== '\n') {
        index += 1
      }
      output += '\n'
      continue
    }

    if (ch === '/' && next === '*') {
      blockDepth = 1
      index += 1
      continue
    }

    output += ch
  }

  return output
}

function isRustLifetimeQuote(source, index) {
  if (source[index] !== "'") return false
  const next = source[index + 1] || ''
  return /[A-Za-z_]/.test(next)
}

function codeLines(code) {
  return code
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
}

function codeDependencyPrefixes(code) {
  const prefixes = new Set()
  const regex = /\b(?:std|crate|hxrt)::[A-Za-z0-9_:]+/g
  let match = null
  while ((match = regex.exec(code)) != null) {
    prefixes.add(match[0].split('::').slice(0, 2).join('::'))
  }
  return Array.from(prefixes).sort()
}

function usePrefixes(code) {
  const imports = []
  const regex = /^\s*use\s+([^;]+);/gm
  let match = null
  while ((match = regex.exec(code)) != null) {
    imports.push(match[1].trim())
  }
  return imports
}

function hasAllowedPrefix(value, prefixes) {
  return prefixes.some((prefix) => value === prefix || value.startsWith(`${prefix}::`) || value.startsWith(`${prefix}::{`) || value.startsWith(`${prefix} as `))
}

function requireStringArray(entry, field, allowEmpty = false) {
  const value = entry[field]
  if (!Array.isArray(value)) {
    fail(`${entry.path || '<unknown>'} must contain ${field} array`)
    return []
  }
  if (!allowEmpty && value.length === 0) {
    fail(`${entry.path || '<unknown>'} must contain at least one ${field} entry`)
  }
  for (const item of value) {
    if (typeof item !== 'string' || item.trim().length === 0) {
      fail(`${entry.path || '<unknown>'} contains a non-string/empty ${field} entry`)
    }
  }
  return value
}

function requireNonEmptyString(entry, field) {
  const value = entry[field]
  if (typeof value !== 'string' || value.trim().length === 0) {
    fail(`${entry.path || '<unknown>'} must contain non-empty ${field}`)
    return ''
  }
  return value
}

function checkForbiddenCode(path, code) {
  const forbidden = [
    { label: 'raw Rust injection marker', regex: /__rust__/ },
    { label: 'raw ERaw marker', regex: /\bERaw\b/ },
    { label: 'Dynamic payload', regex: /\bDynamic\b/ },
    { label: 'Rust Any/type erasure', regex: /\bstd::any\b|\bAny\b|\bTypeId\b|Box\s*<\s*dyn\b/ },
    { label: 'thread-local registry', regex: /\bthread_local!\s*\(/ },
    { label: 'lazy global registry', regex: /\blazy_static!\s*\(|\bOnceLock\b|\bstatic\s+mut\b/ }
  ]

  for (const rule of forbidden) {
    if (rule.regex.test(code)) {
      fail(`${path} contains forbidden native-helper growth pattern (${rule.label})`)
    }
  }
}

if (!fs.existsSync(manifestPath)) {
  fail(`missing native facade manifest: ${manifestPath}`)
  process.exit(process.exitCode)
}

let manifest = null
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
} catch (error) {
  fail(`invalid JSON in ${manifestPath}: ${error.message}`)
  process.exit(process.exitCode)
}

if (manifest == null || typeof manifest !== 'object') {
  fail(`${manifestPath} must contain a JSON object`)
}
if (manifest.schemaVersion !== 1) {
  fail(`${manifestPath} schemaVersion must be 1`)
}
if (!Array.isArray(manifest.entries)) {
  fail(`${manifestPath} must contain entries array`)
}

const trackedHelpers = gitTrackedUnder(helperRoot)
  .filter((path) => path.startsWith(`${helperRoot}/`) && path.endsWith('.rs'))
  .sort()
const trackedSet = new Set(trackedHelpers)
const manifestPaths = []

for (const entry of manifest.entries) {
  if (entry == null || typeof entry !== 'object') {
    fail(`${manifestPath} contains a non-object entry`)
    continue
  }

  const path = requireNonEmptyString(entry, 'path')
  if (!path.startsWith(`${helperRoot}/`) || !path.endsWith('.rs')) {
    fail(`${path} must be a std/rust/native/*.rs helper path`)
  }
  if (manifestPaths.includes(path)) {
    fail(`${manifestPath} contains duplicate helper entry: ${path}`)
  }
  manifestPaths.push(path)

  requireStringArray(entry, 'ownerFacades')
  requireStringArray(entry, 'allowedUsePrefixes', true)
  requireStringArray(entry, 'allowedDependencyPrefixes', true)
  requireStringArray(entry, 'allowedRuntimeDependencies', true)
  requireStringArray(entry, 'forbiddenGrowth')
  requireNonEmptyString(entry, 'whyNotLoweringToday')
  requireNonEmptyString(entry, 'evidenceOwner')

  if (!allowedClassifications.has(entry.classification)) {
    fail(`${path} has invalid classification: ${entry.classification}`)
  }
  if (!allowedRuntimeContracts.has(entry.runtimeContract)) {
    fail(`${path} has invalid runtimeContract: ${entry.runtimeContract}`)
  }
  if (!Number.isInteger(entry.codeLineBudget) || entry.codeLineBudget <= 0) {
    fail(`${path} must contain a positive integer codeLineBudget`)
  }
}

const manifestSet = new Set(manifestPaths)
const missingEntries = trackedHelpers.filter((path) => !manifestSet.has(path))
const staleEntries = manifestPaths.filter((path) => !trackedSet.has(path))

if (missingEntries.length > 0) {
  fail(`native facade manifest missing tracked helper files:\n${summarize(missingEntries, 30)}`)
}
if (staleEntries.length > 0) {
  fail(`native facade manifest references non-tracked helper files:\n${summarize(staleEntries, 30)}`)
}

for (const entry of manifest.entries) {
  const path = entry.path
  if (!trackedSet.has(path)) continue

  const raw = fs.readFileSync(path, 'utf8')
  const code = stripRustComments(raw)
  const lines = codeLines(code)
  const imports = usePrefixes(code)
  const deps = codeDependencyPrefixes(code)
  const allowedImports = entry.allowedUsePrefixes
  const allowedDeps = entry.allowedDependencyPrefixes

  checkForbiddenCode(path, code)

  const unexpectedImports = imports.filter((value) => !hasAllowedPrefix(value, allowedImports))
  if (unexpectedImports.length > 0) {
    fail(`${path} contains use imports outside manifest allowedUsePrefixes:\n${summarize(unexpectedImports, 20)}`)
  }

  const unexpectedDeps = deps.filter((value) => !allowedDeps.includes(value))
  if (unexpectedDeps.length > 0) {
    fail(`${path} references dependency prefixes outside manifest allowedDependencyPrefixes:\n${summarize(unexpectedDeps, 20)}`)
  }

  if (entry.runtimeContract === 'no-hxrt' && deps.some((value) => value.startsWith('hxrt::'))) {
    fail(`${path} is runtimeContract=no-hxrt but references hxrt`)
  }
  if (entry.runtimeContract === 'hxrt-bridge' && !entry.allowedRuntimeDependencies.includes('hxrt')) {
    fail(`${path} is runtimeContract=hxrt-bridge but allowedRuntimeDependencies does not list hxrt`)
  }

  if (lines.length > entry.codeLineBudget) {
    fail(`${path} has ${lines.length} code lines, above manifest codeLineBudget ${entry.codeLineBudget}`)
  }
}

if (process.exitCode) {
  process.exit(process.exitCode)
}

console.log(
  `[ci:guards] OK: native facade manifest covers ${trackedHelpers.length} helper(s) with comment-stripped dependency and growth checks`
)
