#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const { discoverHaxeSurface: discoverSurface } = require('./haxe-public-surface')

const repoRoot = path.resolve(__dirname, '..', '..')
const defaultManifestPath = path.join(repoRoot, 'docs', 'public-compatibility-manifest.json')
const reviewPath = path.join(repoRoot, 'docs', 'pre-1.0-compatibility-review.md')
const sourceRoots = ['src/reflaxe/rust', 'std']
const sourceRoot = path.join(repoRoot, 'src', 'reflaxe', 'rust')
const stdRoot = path.join(repoRoot, 'std')
const internalHelperPolicyPath = path.join(sourceRoot, 'analyze', 'InternalHelperBoundary.hx')
const classes = new Set([
  'stable-candidate',
  'qualified-stable-candidate',
  'experimental',
  'excluded-internal'
])
const statuses = new Set(['active', 'deprecated', 'reserved'])
const admissions = new Set(['candidate', 'admitted', 'experimental', 'internal'])
const evidenceKinds = new Set(['file', 'npm-script', 'bead'])
const evidenceLevels = new Set([
  'structural',
  'source-contract',
  'documentation',
  'compile',
  'generated-output',
  'semantic-runtime',
  'target-runtime',
  'policy',
  'release',
  'review-record'
])
const strongAdmissionEvidence = new Set([
  'compile',
  'generated-output',
  'semantic-runtime',
  'target-runtime',
  'policy',
  'release'
])
const beginMarker = '<!-- BEGIN GENERATED PUBLIC COMPATIBILITY SUMMARY -->'
const endMarker = '<!-- END GENERATED PUBLIC COMPATIBILITY SUMMARY -->'

const metadataPolicies = {
  async: ['marker on an eligible function; no arguments', 'absent'],
  await: ['marker on an eligible expression/function boundary; no arguments', 'absent'],
  haxeMetal: ['marker on a type or field; no arguments', 'absent'],
  rustAllowRaw: ['marker on the single owning low-level type; no arguments', 'absent'],
  rustAsync: ['marker on an eligible function; no arguments', 'absent'],
  rustAwait: ['marker on an eligible expression/function boundary; no arguments', 'absent'],
  rustCargo: ['exactly one compile-time constant object or raw string parameter', 'absent'],
  rustDerive: ['one or more Rust derive names encoded as compile-time strings', 'absent'],
  rustExtraSrc: ['one compile-time constant repository-relative source path', 'absent'],
  rustExtraSrcDir: ['one compile-time constant repository-relative directory path', 'absent'],
  rustGeneric: ['one compile-time string or string-array Rust-bound declaration', 'absent'],
  rustImpl: ['marker-only trait path, body-string form, or documented object/forType form', 'absent'],
  rustMetal: ['marker on a type or field; no arguments', 'absent'],
  rustMutating: ['compiler-recognized marker; no arguments', 'absent'],
  rustNativeWrapper: ['reserved compiler marker; application use rejected', 'absent'],
  rustRepresentation: ['reserved compiler marker; application use rejected', 'absent'],
  rustReturn: ['compiler-recognized marker; no arguments', 'absent'],
  rustTest: ['marker, constant test name, or documented object form with serial defaulting to true', 'absent']
}

const metadataFormPolicies = {
  'structured object dependency form': '{ name:String, ?version:String, ?features:Array<String>, ?optional:Bool, ?defaultFeatures:Bool, ?path:String, ?git:String, ?branch:String, ?tag:String, ?rev:String, ?package:String }',
  'raw string passthrough form': 'one compile-time constant raw Cargo dependency line',
  'marker-only local emitted type': 'one compile-time constant Rust trait path string',
  'body-string and object/forType forms': 'documented string/object escape grammar; experimental'
}

const definePolicyOverrides = {
  async_tokio_adapter: ['presence flag', 'disabled'],
  reflaxe_rust_profile: ['portable|metal', 'portable'],
  rust_cargo_cmd: ['executable path or command name', 'cargo'],
  rust_cargo_deps: ['raw TOML dependency lines', 'unset'],
  rust_cargo_deps_file: ['filesystem path', 'unset'],
  rust_cargo_features: ['comma-separated Cargo feature names', 'empty'],
  rust_cargo_jobs: ['positive integer', 'Cargo default'],
  rust_cargo_subcommand: ['build|check|test|clippy|run', 'build'],
  rust_cargo_target_dir: ['filesystem path', 'Cargo default'],
  rust_cargo_toml: ['filesystem path', 'generated manifest'],
  rust_crate: ['valid Cargo crate name', 'derived from compilation context'],
  rust_extra_src: ['filesystem directory path', 'unset'],
  rust_hxrt_features: ['comma-separated hxrt feature names', 'inferred feature set'],
  rust_output: ['filesystem directory path', 'unset; Rust generation requires a value'],
  rust_target: ['Cargo target triple', 'host target'],
  rust_string_non_nullable: ['presence flag', 'enabled by default only in metal when no string-mode define is present'],
  rust_string_nullable: ['presence flag', 'enabled by default only in portable when no string-mode define is present']
}

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
  if (fs.existsSync(root)) visit(root)
  return result.sort()
}

function discoverHaxeSurface(roots = sourceRoots.map((root) => path.join(repoRoot, root))) {
  return discoverSurface(roots, repoRoot)
}

function discoverHaxeTypes() {
  return discoverHaxeSurface().map(({ name, source }) => ({ name, source }))
}

function discoverDefines() {
  const names = new Set()
  const definedCall = /Context\.defined(?:Value)?\(\s*["']([A-Za-z0-9_.-]+)["']/g
  const indirectDefineCall = /\bhasDefine\(\s*["']([A-Za-z0-9_.-]+)["']/g
  const conditional = /^\s*#(?:if|elseif)\s+([A-Za-z_][A-Za-z0-9_]*)/gm
  for (const file of filesUnder(sourceRoot, '.hx')) {
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
      const source = fs.readFileSync(file, 'utf8')
      let match = null
      while ((match = annotation.exec(source)) != null) names.add(match[1])
      while ((match = recognizedLiteral.exec(source)) != null) names.add(match[1])
    }
  }
  return Array.from(names).sort()
}

function requireString(errors, owner, field, label = owner.id || owner.name || '<entry>') {
  if (typeof owner[field] !== 'string' || owner[field].trim().length === 0) {
    fail(errors, `${label} must declare ${field}`)
    return false
  }
  return true
}

function requireStringArray(errors, owner, field, allowEmpty = false) {
  const value = owner[field]
  if (!Array.isArray(value) || (!allowEmpty && value.length === 0)) {
    fail(errors, `${owner.id || owner.name || '<entry>'}.${field} must be ${allowEmpty ? 'an' : 'a non-empty'} array`)
    return false
  }
  for (const item of value) {
    if (typeof item !== 'string' || item.trim().length === 0) {
      fail(errors, `${owner.id || owner.name || '<entry>'}.${field} contains an empty/non-string value`)
    }
  }
  return true
}

function sameStringArray(left, right) {
  return Array.isArray(left) && Array.isArray(right) && left.length === right.length && left.every((value, index) => value === right[index])
}

/**
 * Reads the compiler-owned namespace list that enforces application/helper separation.
 *
 * The Haxe declaration is deliberately a simple string array so the compiler and this package graph
 * share one policy owner without introducing a release-time JSON dependency into user compilation.
 */
function stringArrayFromInternalPolicy(source, field) {
  const expression = new RegExp(`${field}\\s*:\\s*Array<String>\\s*=\\s*\\[([\\s\\S]*?)\\]\\s*;`)
  const match = source.match(expression)
  if (match == null) throw new Error(`cannot read ${field} from InternalHelperBoundary.hx`)
  const values = Array.from(match[1].matchAll(/"([A-Za-z_][A-Za-z0-9_.]*)"/g), (entry) => entry[1])
  if (new Set(values).size !== values.length) throw new Error(`InternalHelperBoundary.${field} contains duplicates`)
  const sorted = [...values].sort()
  if (!sameStringArray(values, sorted)) throw new Error(`InternalHelperBoundary.${field} must be sorted`)
  return values
}

function internalHelperRoots() {
  const source = fs.readFileSync(internalHelperPolicyPath, 'utf8')
  const roots = stringArrayFromInternalPolicy(source, 'applicationInternalRoots')
  if (roots.length === 0) throw new Error('InternalHelperBoundary.applicationInternalRoots must not be empty')
  return roots
}

function internalHelperExceptions() {
  const source = fs.readFileSync(internalHelperPolicyPath, 'utf8')
  return stringArrayFromInternalPolicy(source, 'applicationPublicExceptions')
}

function belongsToInternalHelperRoot(name, roots, exceptions = []) {
  if (exceptions.some((publicPath) => name === publicPath || name.startsWith(`${publicPath}.`))) return false
  return roots.some((root) => name === root || name.startsWith(`${root}.`))
}

function issueIds() {
  const ids = new Set()
  const issuePath = path.join(repoRoot, '.beads', 'issues.jsonl')
  for (const line of fs.readFileSync(issuePath, 'utf8').split('\n')) {
    if (line.trim().length === 0) continue
    const entry = JSON.parse(line)
    if (entry._type === 'issue' && typeof entry.id === 'string') ids.add(entry.id)
  }
  return ids
}

function validateEvidence(errors, manifest) {
  if (!Array.isArray(manifest.evidence)) {
    fail(errors, 'manifest.evidence must be an array')
    return new Map()
  }
  const packageScripts = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8')).scripts || {}
  const beads = issueIds()
  const result = new Map()
  for (const entry of manifest.evidence) {
    if (!requireString(errors, entry || {}, 'id', 'evidence entry')) continue
    if (result.has(entry.id)) fail(errors, `duplicate evidence id: ${entry.id}`)
    result.set(entry.id, entry)
    if (!evidenceKinds.has(entry.kind)) fail(errors, `evidence ${entry.id} has invalid kind: ${entry.kind}`)
    if (!evidenceLevels.has(entry.level)) fail(errors, `evidence ${entry.id} has invalid level: ${entry.level}`)
    if (entry.kind === 'file') {
      if (requireString(errors, entry, 'path', `evidence ${entry.id}`)) {
        const resolved = path.resolve(repoRoot, entry.path)
        const relative = path.relative(repoRoot, resolved)
        if (relative.startsWith('..') || path.isAbsolute(relative)) fail(errors, `evidence path escapes repository: ${entry.path}`)
        else if (!fs.existsSync(resolved)) fail(errors, `evidence path does not exist: ${entry.path}`)
      }
    } else if (entry.kind === 'npm-script') {
      if (requireString(errors, entry, 'script', `evidence ${entry.id}`) && typeof packageScripts[entry.script] !== 'string') {
        fail(errors, `evidence npm script does not exist: ${entry.script}`)
      }
    } else if (entry.kind === 'bead') {
      if (requireString(errors, entry, 'bead', `evidence ${entry.id}`) && !beads.has(entry.bead)) {
        fail(errors, `evidence Bead does not exist: ${entry.bead}`)
      }
    }
  }
  return result
}

function validateEvidenceIds(errors, owner, evidenceById) {
  if (!requireStringArray(errors, owner, 'evidenceIds')) return
  for (const id of owner.evidenceIds) {
    if (!evidenceById.has(id)) fail(errors, `${owner.id || owner.name || '<entry>'} references unknown evidence ${id}`)
  }
}

function validateAdmittedEntryEvidence(errors, label, entry, contract, evidenceById) {
  if (contract?.admission !== 'admitted') return
  if (!entry.evidenceIds.some((id) => strongAdmissionEvidence.has(evidenceById.get(id)?.level))) {
    fail(errors, `${label} belongs to an admitted contract but lacks operation-specific executable evidence`)
  }
}

function validateNamedInventory(errors, label, discovered, entries) {
  if (!Array.isArray(entries)) {
    fail(errors, `manifest.${label} must be an array`)
    return
  }
  const seen = new Set()
  for (const entry of entries) {
    const value = entry && entry.name
    if (typeof value !== 'string' || value.length === 0) {
      fail(errors, `${label} contains an entry without name`)
      continue
    }
    if (seen.has(value)) fail(errors, `duplicate ${label === 'haxeTypes' ? 'Haxe type' : label} entry: ${value}`)
    seen.add(value)
  }
  const wanted = new Set(discovered.map((entry) => typeof entry === 'string' ? entry : entry.name))
  const missing = Array.from(wanted).filter((value) => !seen.has(value)).sort()
  const stale = Array.from(seen).filter((value) => !wanted.has(value)).sort()
  if (missing.length > 0) fail(errors, `unclassified ${label === 'haxeTypes' ? 'Haxe type' : label}: ${missing.join(', ')}`)
  if (stale.length > 0) fail(errors, `stale ${label} entry: ${stale.join(', ')}`)
}

function validateContract(errors, contract, evidenceById) {
  if (!classes.has(contract.class)) fail(errors, `${contract.id} has noncanonical compatibility class: ${contract.class}`)
  if (!statuses.has(contract.status)) fail(errors, `${contract.id} has invalid lifecycle status: ${contract.status}`)
  if (!admissions.has(contract.admission)) fail(errors, `${contract.id} has invalid admission state: ${contract.admission}`)
  const expectedAdmissions = contract.class === 'experimental'
    ? new Set(['experimental'])
    : contract.class === 'excluded-internal'
      ? new Set(['internal'])
      : new Set(['candidate', 'admitted'])
  if (!expectedAdmissions.has(contract.admission)) {
    fail(errors, `${contract.id} admission state ${contract.admission} is incompatible with ${contract.class}`)
  }
  if (typeof contract.qualification !== 'string') fail(errors, `${contract.id}.qualification must be a string`)
  requireStringArray(errors, contract, 'protectedContract')
  requireStringArray(errors, contract, 'exclusions', true)
  validateEvidenceIds(errors, contract, evidenceById)
  if (contract.admission === 'admitted') {
    if (requireString(errors, contract, 'admissionRecord', contract.id)) {
      const record = evidenceById.get(contract.admissionRecord)
      if (record == null) fail(errors, `${contract.id} admissionRecord references unknown evidence ${contract.admissionRecord}`)
      else if (record.kind !== 'bead' && record.level !== 'release') {
        fail(errors, `${contract.id} admissionRecord must resolve to a reviewed Bead or release record`)
      }
    }
    if (!contract.evidenceIds.some((id) => strongAdmissionEvidence.has(evidenceById.get(id)?.level))) {
      fail(errors, `${contract.id} admitted stable contract requires executable semantic/policy/release evidence`)
    }
  }
  if (contract.status === 'deprecated') {
    if (contract.deprecation == null || typeof contract.deprecation !== 'object') {
      fail(errors, `deprecated contract ${contract.id} must declare deprecation details`)
    } else {
      for (const field of ['deprecatedSince', 'replacement']) {
        if (typeof contract.deprecation[field] !== 'string' || contract.deprecation[field].trim().length === 0) {
          fail(errors, `deprecated contract ${contract.id} must declare ${field}`)
        }
      }
      if (!Number.isInteger(contract.deprecation.earliestRemovalMajor) || contract.deprecation.earliestRemovalMajor < 2) {
        fail(errors, `deprecated contract ${contract.id} must declare earliestRemovalMajor >= 2`)
      }
    }
  } else if (contract.deprecation != null) {
    fail(errors, `non-deprecated contract ${contract.id} must not declare deprecation details`)
  }
}

function validateSurfaceGraph(errors, manifest, discovered, contractsById, evidenceById) {
  validateNamedInventory(errors, 'haxeTypes', discovered, manifest.haxeTypes)
  const discoveredByName = new Map(discovered.map((entry) => [entry.name, entry]))
  for (const type of manifest.haxeTypes || []) {
    const actual = discoveredByName.get(type.name)
    if (actual == null) continue
    if (!contractsById.has(type.contract)) fail(errors, `haxeTypes ${type.name} references unknown contract ${type.contract}`)
    validateEvidenceIds(errors, type, evidenceById)
    validateAdmittedEntryEvidence(errors, `Haxe type ${type.name}`, type, contractsById.get(type.contract), evidenceById)
    if (type.source !== actual.source) fail(errors, `type source drift for ${type.name}: expected ${actual.source}`)
    if (type.kind !== actual.kind) fail(errors, `type kind drift for ${type.name}: expected ${actual.kind}`)
    if (type.signature !== actual.signature) fail(errors, `type signature drift for ${type.name}: expected ${actual.signature}`)
    if (!sameStringArray(type.directTypeReferences, actual.directTypeReferences)) {
      fail(errors, `direct type-reference drift for ${type.name}: expected ${actual.directTypeReferences.join(', ')}`)
    }
    if (!sameStringArray(type.transitiveTypeReferences, actual.transitiveTypeReferences)) {
      fail(errors, `transitive type-reference drift for ${type.name}: expected ${actual.transitiveTypeReferences.join(', ')}`)
    }
    if (!Array.isArray(type.operations)) {
      fail(errors, `${type.name}.operations must be an array`)
      continue
    }
    const actualById = new Map(actual.operations.map((entry) => [entry.id, entry]))
    const recordedById = new Map()
    for (const operation of type.operations) {
      if (recordedById.has(operation.id)) fail(errors, `duplicate operation ${type.name}#${operation.id}`)
      recordedById.set(operation.id, operation)
      const expected = actualById.get(operation.id)
      if (expected == null) {
        fail(errors, `operation graph drift for ${type.name}: stale ${operation.id}`)
        continue
      }
      if (operation.kind !== expected.kind || operation.name !== expected.name) {
        fail(errors, `operation identity drift for ${type.name}#${operation.id}`)
      }
      if (operation.signature !== expected.signature) {
        fail(errors, `operation signature drift for ${type.name}#${operation.id}: expected ${expected.signature}`)
      }
      if (!sameStringArray(operation.typeReferences, expected.typeReferences)) {
        fail(errors, `operation type-reference drift for ${type.name}#${operation.id}: expected ${expected.typeReferences.join(', ')}`)
      }
      if (!contractsById.has(operation.contract)) fail(errors, `operation ${type.name}#${operation.id} references unknown contract ${operation.contract}`)
      validateEvidenceIds(errors, { ...operation, id: `${type.name}#${operation.id}` }, evidenceById)
      validateAdmittedEntryEvidence(errors, `operation ${type.name}#${operation.id}`, operation, contractsById.get(operation.contract), evidenceById)
    }
    const missing = actual.operations.filter((entry) => !recordedById.has(entry.id)).map((entry) => entry.id)
    if (missing.length > 0) fail(errors, `operation graph drift for ${type.name}: missing ${missing.join(', ')}`)
  }
}

function validateInternalHelperBoundary(errors, manifest, contractsById, roots, exceptions) {
  for (const type of manifest.haxeTypes || []) {
    const contract = contractsById.get(type.contract)
    const internalContract = contract?.class === 'excluded-internal' && contract?.admission === 'internal'
    const sealedPath = belongsToInternalHelperRoot(type.name, roots, exceptions)
    if (sealedPath && !internalContract) {
      fail(errors, `type in internal application namespace must use an internal-helper contract: ${type.name} uses ${type.contract}`)
    }
    if (internalContract && !sealedPath) {
      fail(errors, `internal-helper type is not sealed by InternalHelperBoundary.applicationInternalRoots: ${type.name}`)
    }
  }
  for (const publicPath of exceptions) {
    const type = (manifest.haxeTypes || []).find((entry) => entry.name === publicPath)
    if (type == null) fail(errors, `internal-helper public exception does not resolve to a shipped Haxe type: ${publicPath}`)
    else if (contractsById.get(type.contract)?.admission === 'internal') {
      fail(errors, `internal-helper public exception must have an explicit public compatibility contract: ${publicPath}`)
    }
  }
}

function transitiveReferencesFor(referenceNames, typesByName) {
  const seen = new Set()
  const pending = [...referenceNames]
  while (pending.length > 0) {
    const name = pending.shift()
    if (seen.has(name)) continue
    seen.add(name)
    const referenced = typesByName.get(name)
    for (const child of referenced?.directTypeReferences || []) {
      if (!seen.has(child)) pending.push(child)
    }
  }
  return Array.from(seen).sort()
}

function validateAdmittedReferenceClosure(errors, manifest, contractsById) {
  const typesByName = new Map((manifest.haxeTypes || []).map((entry) => [entry.name, entry]))

  function validate(ownerLabel, references) {
    for (const reference of transitiveReferencesFor(references, typesByName)) {
      const type = typesByName.get(reference)
      if (type == null) {
        fail(errors, `${ownerLabel} has unresolved transitive public type ${reference}`)
        continue
      }
      const contract = contractsById.get(type.contract)
      if (contract?.admission !== 'admitted'
        || (contract.class !== 'stable-candidate' && contract.class !== 'qualified-stable-candidate')) {
        fail(errors, `${ownerLabel} has transitive public type ${reference} governed by ${contract?.admission || 'unknown'} contract ${type.contract}`)
      }
    }
  }

  for (const type of manifest.haxeTypes || []) {
    const typeContract = contractsById.get(type.contract)
    if (typeContract?.admission === 'admitted') {
      validate(`admitted type ${type.name}`, type.directTypeReferences || [])
    }
    for (const operation of type.operations || []) {
      const operationContract = contractsById.get(operation.contract)
      if (operationContract?.admission === 'admitted') {
        validate(`admitted operation ${type.name}#${operation.id}`, operation.typeReferences || [])
      }
    }
  }
}

function loadAndValidate(manifestPath) {
  const errors = []
  let manifest = null
  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  } catch (error) {
    return { errors: [`cannot read public compatibility manifest: ${error.message}`], manifest: null }
  }
  if (manifest.schemaVersion !== 2) fail(errors, 'manifest.schemaVersion must be 2')
  if (!sameStringArray(manifest.classes, Array.from(classes))) {
    fail(errors, `manifest.classes must be exactly: ${Array.from(classes).join(', ')}`)
  }
  if (!sameStringArray(manifest.surfaceScope?.sourceRoots, sourceRoots)) {
    fail(errors, `manifest.surfaceScope.sourceRoots must be ${sourceRoots.join(', ')}`)
  }
  const evidenceById = validateEvidence(errors, manifest)
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
    validateContract(errors, contract, evidenceById)
  }

  let discovered = []
  let helperRoots = []
  let helperExceptions = []
  try {
    helperRoots = internalHelperRoots()
    helperExceptions = internalHelperExceptions()
  } catch (error) {
    fail(errors, `cannot load internal-helper boundary policy: ${error.message}`)
  }
  try {
    discovered = discoverHaxeSurface()
  } catch (error) {
    fail(errors, `cannot discover package Haxe surface: ${error.message}`)
  }
  validateSurfaceGraph(errors, manifest, discovered, contractsById, evidenceById)
  validateInternalHelperBoundary(errors, manifest, contractsById, helperRoots, helperExceptions)
  validateAdmittedReferenceClosure(errors, manifest, contractsById)
  validateNamedInventory(errors, 'metadata', discoverMetadata(), manifest.metadata)
  validateNamedInventory(errors, 'defines', discoverDefines(), manifest.defines)

  for (const group of ['metadata', 'defines', 'reports', 'generatedArtifacts']) {
    for (const entry of manifest[group] || []) {
      const label = entry.name || entry.filename || entry.id || '<entry>'
      if (typeof entry.contract !== 'string' || !contractIds.has(entry.contract)) {
        fail(errors, `${group} ${label} references unknown contract ${entry.contract}`)
      }
      validateEvidenceIds(errors, { ...entry, id: label }, evidenceById)
      validateAdmittedEntryEvidence(errors, `${group} ${label}`, entry, contractsById.get(entry.contract), evidenceById)
      for (const form of entry.forms || []) {
        if (typeof form.name !== 'string' || form.name.length === 0) fail(errors, `${group} ${entry.name} contains a form without a name`)
        if (!contractIds.has(form.contract)) fail(errors, `${group} ${entry.name} form ${form.name || '<form>'} references unknown contract ${form.contract}`)
        requireString(errors, form, 'grammar', `${group} ${entry.name} form ${form.name || '<form>'}`)
        requireString(errors, form, 'default', `${group} ${entry.name} form ${form.name || '<form>'}`)
      }
      if (group === 'metadata') {
        requireString(errors, entry, 'grammar', `metadata ${entry.name}`)
        requireString(errors, entry, 'default', `metadata ${entry.name}`)
      } else if (group === 'defines') {
        requireString(errors, entry, 'valueGrammar', `define ${entry.name}`)
        requireString(errors, entry, 'default', `define ${entry.name}`)
      }
    }
  }
  return { errors, manifest }
}

function evidenceId(reference) {
  return fs.existsSync(path.join(repoRoot, reference)) ? `file:${reference}` : `bead:${reference}`
}

function evidenceLevel(reference) {
  if (reference.startsWith('docs/')) return 'documentation'
  if (reference.startsWith('std/') || reference.startsWith('src/')) return 'source-contract'
  if (reference.startsWith('test/')) return 'target-runtime'
  if (reference.startsWith('scripts/')) return 'policy'
  return 'review-record'
}

function boundaryOwnedContract(name) {
  if (internalHelperExceptions().includes(name)) {
    const exceptions = {
      'reflaxe.rust.macros.RustInjection': 'raw-experimental'
    }
    if (exceptions[name] == null) throw new Error(`public internal-root exception requires explicit compatibility classification: ${name}`)
    return exceptions[name]
  }
  if (belongsToInternalHelperRoot(name, internalHelperRoots())) return 'internal-helper'
  return null
}

function classifyNewType(name) {
  const boundaryContract = boundaryOwnedContract(name)
  if (boundaryContract != null) return boundaryContract
  const exact = {
    ArrayTools: 'portable-core',
    Date: 'portable-core',
    Lambda: 'portable-core',
    StringBuf: 'portable-core',
    StringTools: 'portable-core',
    Sys: 'portable-sys-core',
    'SysTypes.SysPrintValue': 'portable-sys-core',
    'haxe.functional.Result': 'portable-core',
    'haxe.json.Value': 'portable-core',
    'sys.io.Stderr': 'portable-sys-core',
    'sys.io.Stdin': 'portable-sys-core',
    'sys.io.Stdout': 'portable-sys-core',
    'sys.net._SocketIO.SocketInput': 'portable-net-tcp',
    'sys.net._SocketIO.SocketOutput': 'portable-net-tcp'
  }
  return exact[name] || null
}

function definePolicy(name) {
  return definePolicyOverrides[name] || ['presence flag', 'disabled']
}

function refreshManifest(manifest) {
  const evidence = new Map()
  evidence.set('test:public-compatibility', {
    id: 'test:public-compatibility',
    kind: 'npm-script',
    script: 'test:public-compatibility',
    level: 'structural'
  })
  for (const entry of manifest.evidence || []) evidence.set(entry.id, entry)
  const contracts = (manifest.contracts || []).map((contract) => {
    const references = contract.evidence || (contract.evidenceIds || []).map((id) => evidence.get(id)).filter(Boolean)
    const ids = []
    for (const reference of references) {
      if (typeof reference !== 'string') {
        ids.push(reference.id)
        continue
      }
      const id = evidenceId(reference)
      ids.push(id)
      if (!evidence.has(id)) {
        evidence.set(id, fs.existsSync(path.join(repoRoot, reference))
          ? { id, kind: 'file', path: reference, level: evidenceLevel(reference) }
          : { id, kind: 'bead', bead: reference, level: 'review-record' })
      }
    }
    const upgraded = { ...contract }
    delete upgraded.evidence
    upgraded.admission = upgraded.admission || (contract.class === 'experimental' ? 'experimental' : contract.class === 'excluded-internal' ? 'internal' : 'candidate')
    upgraded.evidenceIds = Array.from(new Set([...ids, 'test:public-compatibility'])).sort()
    if (upgraded.id === 'haxe-metal-alias' && upgraded.deprecation == null) {
      upgraded.deprecation = {
        deprecatedSince: '0.85.1',
        replacement: '@:rustMetal',
        earliestRemovalMajor: 2
      }
    }
    return upgraded
  })
  const previousTypes = new Map((manifest.haxeTypes || []).map((entry) => [entry.name, entry]))
  const discovered = discoverHaxeSurface()
  const haxeTypes = discovered.map((type) => {
    const previous = previousTypes.get(type.name)
    const contract = boundaryOwnedContract(type.name) || previous?.contract || classifyNewType(type.name)
    if (contract == null) throw new Error(`new Haxe type requires explicit compatibility classification: ${type.name}`)
    const previousOperations = new Map((previous?.operations || []).map((entry) => [entry.id, entry]))
    return {
      name: type.name,
      source: type.source,
      kind: type.kind,
      signature: type.signature,
      contract,
      evidenceIds: previous?.evidenceIds || ['test:public-compatibility'],
      directTypeReferences: type.directTypeReferences,
      transitiveTypeReferences: type.transitiveTypeReferences,
      operations: type.operations.map((operation) => ({
        id: operation.id,
        kind: operation.kind,
        name: operation.name,
        signature: operation.signature,
        contract: previousOperations.get(operation.id)?.contract || contract,
        evidenceIds: previousOperations.get(operation.id)?.evidenceIds || ['test:public-compatibility'],
        typeReferences: operation.typeReferences
      }))
    }
  })
  const metadata = (manifest.metadata || []).map((entry) => {
    const policy = metadataPolicies[entry.name]
    if (policy == null) throw new Error(`metadata policy missing for ${entry.name}`)
    return {
      ...entry,
      grammar: entry.grammar || policy[0],
      default: entry.default || policy[1],
      evidenceIds: entry.evidenceIds || ['test:public-compatibility'],
      ...(entry.forms == null ? {} : {
        forms: entry.forms.map((form) => ({
          ...form,
          grammar: form.grammar || metadataFormPolicies[form.name] || 'documented form grammar',
          default: form.default || 'absent'
        }))
      })
    }
  })
  const defines = (manifest.defines || []).map((entry) => {
    const [valueGrammar, defaultValue] = definePolicy(entry.name)
    return {
      ...entry,
      valueGrammar: entry.valueGrammar || valueGrammar,
      default: entry.default || defaultValue,
      evidenceIds: entry.evidenceIds || ['test:public-compatibility']
    }
  })
  const withEvidence = (entries) => (entries || []).map((entry) => ({
    ...entry,
    evidenceIds: entry.evidenceIds || ['test:public-compatibility']
  }))
  return {
    schemaVersion: 2,
    surfaceScope: {
      sourceRoots,
      packageBoundary: 'Haxe declarations merged into the installed Haxelib classPath; runtime Rust and vendored Reflaxe are governed as package artifacts, not application Haxe APIs.'
    },
    classes: manifest.classes,
    evidence: Array.from(evidence.values()).sort((left, right) => left.id.localeCompare(right.id)),
    contracts,
    haxeTypes,
    metadata,
    defines,
    reports: withEvidence(manifest.reports),
    generatedArtifacts: withEvidence(manifest.generatedArtifacts)
  }
}

function renderSummary(manifest) {
  const operationCount = manifest.haxeTypes.reduce((count, type) => count + type.operations.length, 0)
  const lines = [beginMarker]
  lines.push('| Contract | Class | Admission | Status | Qualification |')
  lines.push('| --- | --- | --- | --- | --- |')
  for (const contract of manifest.contracts) {
    lines.push(`| \`${contract.id}\` | \`${contract.class}\` | \`${contract.admission}\` | \`${contract.status}\` | ${contract.qualification || 'None'} |`)
  }
  lines.push('')
  lines.push(`Inventory: ${manifest.haxeTypes.length} shipped Haxe types, ${operationCount} public operations, ${manifest.metadata.length} metadata names, ${manifest.defines.length} defines, ${(manifest.reports || []).length} JSON reports, ${(manifest.generatedArtifacts || []).length} generated-artifact contracts, and ${manifest.evidence.length} validated evidence records.`)
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

function writeReview(rendered) {
  const review = fs.readFileSync(reviewPath, 'utf8')
  const begin = review.indexOf(beginMarker)
  const end = review.indexOf(endMarker)
  if (begin < 0 || end < begin) throw new Error('compatibility review is missing generated summary markers')
  const next = `${review.slice(0, begin)}${rendered.trimEnd()}${review.slice(end + endMarker.length)}`
  fs.writeFileSync(reviewPath, next)
}

function argumentValue(args, name, fallback) {
  const index = args.indexOf(name)
  return index >= 0 ? args[index + 1] : fallback
}

function main() {
  const args = process.argv.slice(2)
  const manifestPath = path.resolve(argumentValue(args, '--manifest', defaultManifestPath))
  if (args.includes('--refresh-manifest')) {
    const current = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
    const refreshed = refreshManifest(current)
    fs.writeFileSync(manifestPath, `${JSON.stringify(refreshed, null, 2)}\n`)
    console.log(`[public-compatibility] refreshed ${path.relative(repoRoot, manifestPath)}`)
    return
  }
  const { errors, manifest } = loadAndValidate(manifestPath)
  if (manifest != null && errors.length === 0) {
    const rendered = renderSummary(manifest)
    if (args.includes('--render')) {
      process.stdout.write(rendered)
      return
    }
    if (args.includes('--write-review')) {
      writeReview(rendered)
      console.log('[public-compatibility] refreshed docs/pre-1.0-compatibility-review.md')
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

module.exports = {
  discoverDefines,
  discoverHaxeSurface,
  discoverHaxeTypes,
  discoverMetadata,
  internalHelperExceptions,
  internalHelperRoots,
  loadAndValidate,
  refreshManifest,
  renderSummary
}
