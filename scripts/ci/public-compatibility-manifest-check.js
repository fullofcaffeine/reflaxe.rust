#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const defaultManifestPath = path.join(repoRoot, 'docs', 'public-compatibility-manifest.json')
const reviewPath = path.join(repoRoot, 'docs', 'pre-1.0-compatibility-review.md')
const stdRoot = path.join(repoRoot, 'std', 'rust')
const sourceRoot = path.join(repoRoot, 'src', 'reflaxe', 'rust')
const classes = new Set([
  'stable-candidate',
  'qualified-stable-candidate',
  'experimental',
  'excluded-internal'
])
const statuses = new Set(['active', 'deprecated', 'reserved'])
const beginMarker = '<!-- BEGIN GENERATED PUBLIC COMPATIBILITY SUMMARY -->'
const endMarker = '<!-- END GENERATED PUBLIC COMPATIBILITY SUMMARY -->'

function fail(errors, message) {
  errors.push(message)
}

function filesUnder(root, extension) {
  const result = []
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name)
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile() && full.endsWith(extension)) result.push(full)
    }
  }
  visit(root)
  return result.sort()
}

function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, (value) => value.replace(/[^\n]/g, ' '))
    .replace(/\/\/[^\n]*/g, '')
}

/**
 * Why: Haxe modules may export secondary types whose import path includes the module name.
 * What: Enumerates every non-private top-level declaration shipped from `std/rust`.
 * How: Uses the declared package plus Haxe's primary/secondary module path rule; private
 * declarations are intentionally excluded because application code cannot import them.
 */
function discoverHaxeTypes() {
  const discovered = []
  const declaration = /^\s*(private\s+)?(?:(?:extern|enum)\s+)?(?:class|interface|abstract|enum|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)/gm
  for (const file of filesUnder(stdRoot, '.hx')) {
    const source = stripComments(fs.readFileSync(file, 'utf8'))
    const packageMatch = source.match(/^\s*package(?:\s+([A-Za-z0-9_.]+))?\s*;/m)
    if (packageMatch == null) continue
    const packageName = packageMatch[1] || ''
    const moduleName = path.basename(file, '.hx')
    let match = null
    while ((match = declaration.exec(source)) != null) {
      if (match[1]) continue
      const typeName = match[2]
      const prefix = packageName.length > 0 ? `${packageName}.` : ''
      const name = typeName === moduleName
        ? `${prefix}${typeName}`
        : `${prefix}${moduleName}.${typeName}`
      discovered.push({
        name,
        source: path.relative(repoRoot, file).split(path.sep).join('/')
      })
    }
  }
  return discovered.sort((left, right) => left.name.localeCompare(right.name))
}

function discoverDefines() {
  const names = new Set()
  const definedCall = /Context\.defined(?:Value)?\(\s*["']([A-Za-z0-9_.-]+)["']/g
  const indirectDefineCall = /\bhasDefine\(\s*["']([A-Za-z0-9_.-]+)["']/g
  const conditional = /^\s*#(?:if|elseif)\s+([A-Za-z_][A-Za-z0-9_]*)/gm
  for (const file of filesUnder(sourceRoot, '.hx')) {
    // The call-shaped pattern is specific enough to scan raw source. A generic comment stripper
    // would misread `/*` inside compiler-owned raw target strings and hide later define calls.
    const source = fs.readFileSync(file, 'utf8')
    let match = null
    while ((match = definedCall.exec(source)) != null) {
      if (match[1] !== 'target.name') names.add(match[1])
    }
    while ((match = indirectDefineCall.exec(source)) != null) names.add(match[1])
  }
  for (const file of filesUnder(stdRoot, '.hx')) {
    const source = fs.readFileSync(file, 'utf8')
    let match = null
    while ((match = conditional.exec(source)) != null) {
      if (match[1].startsWith('rust_') || match[1].startsWith('reflaxe_rust_') || match[1] === 'async_tokio_adapter') {
        names.add(match[1])
      }
    }
  }
  return Array.from(names).sort()
}

function discoverMetadata() {
  const names = new Set()
  const annotation = /@:(rust[A-Za-z0-9_]*|haxeMetal|async|await)\b/g
  const recognizedLiteral = /["']:?(rust[A-Z][A-Za-z0-9_]*|haxeMetal|async|await)["']/g
  for (const root of [sourceRoot, stdRoot]) {
    for (const file of filesUnder(root, '.hx')) {
      // Compiler metadata literals can appear after raw Rust strings containing comment tokens.
      // Scan raw source and keep the target-specific name filter narrow instead of truncating it.
      const source = fs.readFileSync(file, 'utf8')
      let match = null
      while ((match = annotation.exec(source)) != null) names.add(match[1])
      while ((match = recognizedLiteral.exec(source)) != null) names.add(match[1])
    }
  }
  return Array.from(names).sort()
}

function requireStringArray(errors, owner, field, allowEmpty = false) {
  const value = owner[field]
  if (!Array.isArray(value) || (!allowEmpty && value.length === 0)) {
    fail(errors, `${owner.id || '<entry>'}.${field} must be ${allowEmpty ? 'an' : 'a non-empty'} array`)
    return
  }
  for (const item of value) {
    if (typeof item !== 'string' || item.trim().length === 0) {
      fail(errors, `${owner.id || '<entry>'}.${field} contains an empty/non-string value`)
    }
  }
}

function validateNamedInventory(errors, label, discovered, entries, key = 'name') {
  if (!Array.isArray(entries)) {
    fail(errors, `manifest.${label} must be an array`)
    return
  }
  const seen = new Set()
  for (const entry of entries) {
    const value = entry && entry[key]
    if (typeof value !== 'string' || value.length === 0) {
      fail(errors, `${label} contains an entry without ${key}`)
      continue
    }
    if (seen.has(value)) fail(errors, `duplicate ${label === 'haxeTypes' ? 'Haxe type' : label} entry: ${value}`)
    seen.add(value)
    if (typeof entry.contract !== 'string' || entry.contract.length === 0) {
      fail(errors, `${label} ${value} must name a contract`)
    }
  }
  const wanted = new Set(discovered.map((entry) => typeof entry === 'string' ? entry : entry.name))
  const missing = Array.from(wanted).filter((value) => !seen.has(value)).sort()
  const stale = Array.from(seen).filter((value) => !wanted.has(value)).sort()
  if (missing.length > 0) fail(errors, `unclassified ${label === 'haxeTypes' ? 'Haxe type' : label}: ${missing.join(', ')}`)
  if (stale.length > 0) fail(errors, `stale ${label} entry: ${stale.join(', ')}`)
}

function loadAndValidate(manifestPath) {
  const errors = []
  let manifest = null
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  } catch (error) {
    return { errors: [`cannot read public compatibility manifest: ${error.message}`], manifest: null }
  }
  if (manifest.schemaVersion !== 1) fail(errors, 'manifest.schemaVersion must be 1')
  if (!Array.isArray(manifest.contracts)) fail(errors, 'manifest.contracts must be an array')
  const contractIds = new Set()
  const contractsById = new Map()
  for (const contract of manifest.contracts || []) {
    if (contract == null || typeof contract.id !== 'string' || contract.id.length === 0) {
      fail(errors, 'contract entry must have a non-empty id')
      continue
    }
    if (contractIds.has(contract.id)) fail(errors, `duplicate contract id: ${contract.id}`)
    contractIds.add(contract.id)
    contractsById.set(contract.id, contract)
    if (!classes.has(contract.class)) fail(errors, `${contract.id} has noncanonical compatibility class: ${contract.class}`)
    if (!statuses.has(contract.status)) fail(errors, `${contract.id} has invalid lifecycle status: ${contract.status}`)
    if (typeof contract.qualification !== 'string') fail(errors, `${contract.id}.qualification must be a string`)
    requireStringArray(errors, contract, 'protectedContract')
    requireStringArray(errors, contract, 'evidence')
    requireStringArray(errors, contract, 'exclusions', true)
  }

  validateNamedInventory(errors, 'haxeTypes', discoverHaxeTypes(), manifest.haxeTypes)
  validateNamedInventory(errors, 'metadata', discoverMetadata(), manifest.metadata)
  validateNamedInventory(errors, 'defines', discoverDefines(), manifest.defines)

  for (const group of ['haxeTypes', 'memberFamilies', 'metadata', 'defines', 'reports', 'generatedArtifacts']) {
    for (const entry of manifest[group] || []) {
      if (typeof entry.contract === 'string' && !contractIds.has(entry.contract)) {
        fail(errors, `${group} ${entry.name || entry.filename || entry.id || '<entry>'} references unknown contract ${entry.contract}`)
      }
      for (const form of entry.forms || []) {
        if (typeof form.name !== 'string' || form.name.length === 0) fail(errors, `${group} ${entry.name} contains a form without a name`)
        if (!contractIds.has(form.contract)) fail(errors, `${group} ${entry.name} form ${form.name || '<form>'} references unknown contract ${form.contract}`)
      }
    }
  }
  for (const entry of manifest.haxeTypes || []) {
    const owner = contractsById.get(entry.contract)
    if (owner != null && owner.class === 'excluded-internal' && entry.name.startsWith('rust.') && !entry.name.startsWith('rust._internal.')) {
      fail(errors, `internal Rust helper must be private or live under rust._internal: ${entry.name}`)
    }
  }
  for (const family of manifest.memberFamilies || []) requireStringArray(errors, family, 'owners')
  return { errors, manifest }
}

function renderSummary(manifest) {
  const lines = [beginMarker]
  lines.push('| Contract | Class | Status | Qualification |')
  lines.push('| --- | --- | --- | --- |')
  for (const contract of manifest.contracts) {
    lines.push(`| \`${contract.id}\` | \`${contract.class}\` | \`${contract.status}\` | ${contract.qualification || 'None'} |`)
  }
  lines.push('')
  lines.push(`Inventory: ${manifest.haxeTypes.length} shipped Haxe types, ${(manifest.memberFamilies || []).length} admitted member families, ${manifest.metadata.length} metadata names, ${manifest.defines.length} defines, ${(manifest.reports || []).length} JSON reports, and ${(manifest.generatedArtifacts || []).length} generated-artifact contracts.`)
  lines.push(endMarker)
  return `${lines.join('\n')}\n`
}

function validateReview(errors, rendered) {
  const review = fs.readFileSync(reviewPath, 'utf8')
  const begin = review.indexOf(beginMarker)
  const end = review.indexOf(endMarker)
  if (begin < 0 || end < begin) {
    fail(errors, 'compatibility review is missing generated summary markers')
    return
  }
  const actual = `${review.slice(begin, end + endMarker.length)}\n`
  if (actual !== rendered) fail(errors, 'generated compatibility summary is stale; run the manifest renderer and update the review')
}

function argumentValue(args, name, fallback) {
  const index = args.indexOf(name)
  return index >= 0 ? args[index + 1] : fallback
}

function main() {
  const args = process.argv.slice(2)
  const manifestPath = path.resolve(argumentValue(args, '--manifest', defaultManifestPath))
  const { errors, manifest } = loadAndValidate(manifestPath)
  if (manifest != null && errors.length === 0) {
    const rendered = renderSummary(manifest)
    if (args.includes('--render')) {
      process.stdout.write(rendered)
      return
    }
    if (!args.includes('--skip-doc') && manifestPath === defaultManifestPath) validateReview(errors, rendered)
  }
  if (errors.length > 0) {
    for (const error of errors) console.error(`[public-compatibility] ERROR: ${error}`)
    process.exit(1)
  }
  console.log('[public-compatibility] OK')
}

if (require.main === module) main()

module.exports = { discoverDefines, discoverHaxeTypes, discoverMetadata, loadAndValidate, renderSummary }
