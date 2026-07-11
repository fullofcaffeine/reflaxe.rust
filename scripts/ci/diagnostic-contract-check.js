#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const semver = require('semver')

const repoRoot = path.resolve(__dirname, '..', '..')
const defaultManifestPath = path.join(repoRoot, 'docs', 'diagnostic-contract.json')
const registryPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustDiagnostic.hx')
const policyPath = path.join(repoRoot, 'docs', 'diagnostic-identifiers.md')
const severities = new Set(['error', 'warning'])
const statuses = new Set(['active', 'deprecated', 'retired'])

function filesUnder(root, extension) {
  const out = []
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name)
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile() && full.endsWith(extension)) out.push(full)
    }
  }
  visit(root)
  return out.sort()
}

function discoverRegistry() {
  const source = fs.readFileSync(registryPath, 'utf8')
  const pattern = /^\s*var\s+([A-Za-z][A-Za-z0-9]*)\s*=\s*"(HXRS-[A-Z0-9-]+)";/gm
  const entries = []
  let match = null
  while ((match = pattern.exec(source)) != null) entries.push({ member: match[1], id: match[2] })
  return entries
}

function loadAndValidate(manifestPath, skipDoc = false) {
  const errors = []
  let manifest = null
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  } catch (error) {
    return { errors: [`cannot read diagnostic contract: ${error.message}`], manifest: null }
  }
  if (manifest.schemaVersion !== 1) errors.push('manifest.schemaVersion must be 1')
  if (manifest.prefix !== '[HXRS-') errors.push('manifest.prefix must be [HXRS-')
  if (!Array.isArray(manifest.diagnostics)) errors.push('manifest.diagnostics must be an array')

  const registry = discoverRegistry()
  const registryIds = new Set(registry.map((entry) => entry.id))
  const seen = new Set()
  for (const entry of manifest.diagnostics || []) {
    if (entry == null || typeof entry.id !== 'string' || !/^HXRS-[A-Z0-9-]+$/.test(entry.id)) {
      errors.push('diagnostic entry has invalid id')
      continue
    }
    if (seen.has(entry.id)) errors.push(`duplicate diagnostic id: ${entry.id}`)
    seen.add(entry.id)
    if (typeof entry.family !== 'string' || entry.family.length === 0) errors.push(`${entry.id} has invalid family`)
    if (!severities.has(entry.severity)) errors.push(`${entry.id} has invalid severity: ${entry.severity}`)
    if (typeof entry.trigger !== 'string' || entry.trigger.length === 0) errors.push(`${entry.id} has invalid trigger`)
    if (semver.valid(entry.introduced || '') !== entry.introduced) errors.push(`${entry.id} has invalid introduced version`)
    if (!statuses.has(entry.status)) errors.push(`${entry.id} has invalid status`)
    if (entry.status === 'active' && entry.replacement != null) errors.push(`${entry.id} active diagnostics must not name a replacement`)
    if ((entry.status === 'deprecated' || entry.status === 'retired') && (typeof entry.replacement !== 'string' || entry.replacement.length === 0)) {
      errors.push(`${entry.id} ${entry.status} diagnostics must name a replacement`)
    }
  }
  for (const entry of manifest.diagnostics || []) {
    if (typeof entry.replacement !== 'string') continue
    if (entry.replacement === entry.id) errors.push(`${entry.id} must not replace itself`)
    else if (!seen.has(entry.replacement)) errors.push(`${entry.id} replacement is not registered: ${entry.replacement}`)
  }
  const missing = Array.from(registryIds).filter((id) => !seen.has(id)).sort()
  const stale = Array.from(seen).filter((id) => !registryIds.has(id)).sort()
  if (missing.length > 0) errors.push(`missing compiler diagnostic entries: ${missing.join(', ')}`)
  if (stale.length > 0) errors.push(`manifest diagnostics absent from compiler registry: ${stale.join(', ')}`)

  const compilerText = filesUnder(path.join(repoRoot, 'src', 'reflaxe', 'rust'), '.hx')
    .filter((file) => file !== registryPath)
    .map((file) => fs.readFileSync(file, 'utf8'))
    .join('\n')
  for (const entry of registry) {
    if (!compilerText.includes(`RustDiagnosticId.${entry.member}`)) errors.push(`compiler diagnostic is not emitted: ${entry.id}`)
  }

  if (!skipDoc) {
    if (!fs.existsSync(policyPath)) errors.push('diagnostic identifier policy document is missing')
    else {
      const policy = fs.readFileSync(policyPath, 'utf8')
      for (const phrase of ['remainder of the current major', 'exact English wording', 'replacement']) {
        if (!policy.includes(phrase)) errors.push(`diagnostic policy is missing required rule: ${phrase}`)
      }
    }
  }
  return { errors, manifest }
}

function argumentValue(args, name, fallback) {
  const index = args.indexOf(name)
  return index >= 0 ? args[index + 1] : fallback
}

function main() {
  const args = process.argv.slice(2)
  const manifestPath = path.resolve(argumentValue(args, '--manifest', defaultManifestPath))
  const { errors } = loadAndValidate(manifestPath, args.includes('--skip-doc'))
  if (errors.length > 0) {
    for (const error of errors) console.error(`[diagnostic-contract] ERROR: ${error}`)
    process.exit(1)
  }
  console.log('[diagnostic-contract] OK')
}

if (require.main === module) main()

module.exports = { discoverRegistry, loadAndValidate }
