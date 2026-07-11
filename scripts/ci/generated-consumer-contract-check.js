#!/usr/bin/env node

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const Ajv = require('ajv')

const repoRoot = path.resolve(__dirname, '..', '..')
const defaultManifestPath = path.join(repoRoot, 'docs', 'generated-consumer-contract.json')
const baselineRelativePath = 'test/compatibility-baselines/generated-consumer-contract-initial.json'
const defaultBaselinePath = path.join(repoRoot, baselineRelativePath)
const publicManifestPath = path.join(repoRoot, 'docs', 'public-compatibility-manifest.json')
const compilerPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustCompiler.hx')
const allowedTypes = new Set(['array', 'boolean', 'integer', 'number', 'object', 'string', 'null'])

function readJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    throw new Error(`cannot read ${label}: ${error.message}`)
  }
}

function canonicalJson(value) {
  if (Array.isArray(value)) return value.map(canonicalJson)
  if (value == null || typeof value !== 'object') return value
  const out = {}
  for (const key of Object.keys(value).sort()) out[key] = canonicalJson(value[key])
  return out
}

function schemaDigest(schema) {
  return crypto.createHash('sha256').update(JSON.stringify(canonicalJson(schema))).digest('hex')
}

function repoPath(value, owner) {
  if (typeof value !== 'string' || value.length === 0 || path.isAbsolute(value)) {
    throw new Error(`${owner} must be a non-empty repository-relative path`)
  }
  const resolved = path.resolve(repoRoot, value)
  const relative = path.relative(repoRoot, resolved)
  if (relative.startsWith('..') || path.isAbsolute(relative)) throw new Error(`${owner} escapes the repository`)
  return resolved
}

function requireNonEmptyString(value, owner) {
  if (typeof value !== 'string' || value.trim().length === 0) throw new Error(`${owner} must be a non-empty string`)
}

function requireStringArray(value, owner, allowEmpty = false) {
  if (!Array.isArray(value) || (!allowEmpty && value.length === 0)) throw new Error(`${owner} must be ${allowEmpty ? 'an' : 'a non-empty'} array`)
  for (const entry of value) requireNonEmptyString(entry, `${owner}[]`)
  if (new Set(value).size !== value.length) throw new Error(`${owner} contains duplicate values`)
}

function validateAdditiveObjectPolicy(schema, owner = '$') {
  if (schema == null || typeof schema !== 'object') return
  if (schema.type === 'object' && schema.additionalProperties !== true) {
    throw new Error(`${owner} must set additionalProperties=true for additive-field compatibility`)
  }
  for (const [key, child] of Object.entries(schema)) {
    if (key === '$ref') continue
    if (Array.isArray(child)) child.forEach((entry, index) => validateAdditiveObjectPolicy(entry, `${owner}.${key}[${index}]`))
    else if (child != null && typeof child === 'object') validateAdditiveObjectPolicy(child, `${owner}.${key}`)
  }
}

function rootFieldName(jsonPath) {
  const match = /^\$\.([A-Za-z][A-Za-z0-9]*)$/.exec(jsonPath)
  return match == null ? null : match[1]
}

function schemaType(schemaNode, rootSchema) {
  if (schemaNode == null || typeof schemaNode !== 'object') return null
  if (typeof schemaNode.$ref === 'string' && schemaNode.$ref.startsWith('#/$defs/')) {
    const key = schemaNode.$ref.slice('#/$defs/'.length)
    return schemaType(rootSchema.$defs && rootSchema.$defs[key], rootSchema)
  }
  if (typeof schemaNode.type === 'string') return schemaNode.type
  if (Object.hasOwn(schemaNode, 'const')) {
    if (Number.isInteger(schemaNode.const)) return 'integer'
    if (Array.isArray(schemaNode.const)) return 'array'
    if (schemaNode.const == null) return 'null'
    return typeof schemaNode.const
  }
  if (Array.isArray(schemaNode.enum) && schemaNode.enum.length > 0) {
    return Number.isInteger(schemaNode.enum[0]) ? 'integer' : typeof schemaNode.enum[0]
  }
  return null
}

function validateProtectedFields(report, schema) {
  if (!Array.isArray(report.protectedFields) || report.protectedFields.length === 0) {
    throw new Error(`${report.id}.protectedFields must be a non-empty array`)
  }
  const seen = new Set()
  for (const field of report.protectedFields) {
    requireNonEmptyString(field && field.path, `${report.id}.protectedFields.path`)
    if (!allowedTypes.has(field.type)) throw new Error(`${report.id} protected field ${field.path} has invalid type ${field.type}`)
    if (seen.has(field.path)) throw new Error(`${report.id} duplicates protected field ${field.path}`)
    seen.add(field.path)
    const rootName = rootFieldName(field.path)
    if (rootName == null) continue
    if (!Array.isArray(schema.required) || !schema.required.includes(rootName)) {
      throw new Error(`${report.id} protected field ${field.path} is not required by its schema`)
    }
    const actualType = schemaType(schema.properties && schema.properties[rootName], schema)
    if (actualType !== field.type) {
      throw new Error(`${report.id} protected field ${field.path} type ${field.type} disagrees with schema type ${actualType}`)
    }
  }
  for (const required of schema.required || []) {
    if (!seen.has(`$.${required}`)) throw new Error(`${report.id} schema-required field $.${required} is not protected by the manifest`)
  }
}

function dereferenceSchema(node, rootSchema) {
  if (node == null || typeof node !== 'object') return node
  if (typeof node.$ref === 'string' && node.$ref.startsWith('#/$defs/')) {
    const key = node.$ref.slice('#/$defs/'.length)
    return dereferenceSchema(rootSchema.$defs && rootSchema.$defs[key], rootSchema)
  }
  return node
}

function propertySchemas(nodes, property, rootSchema) {
  const out = []
  for (const rawNode of nodes) {
    const node = dereferenceSchema(rawNode, rootSchema)
    if (node == null || typeof node !== 'object') continue
    if (node.properties && node.properties[property]) out.push(node.properties[property])
    for (const branch of node.allOf || []) out.push(...propertySchemas([branch], property, rootSchema))
  }
  return out
}

function itemSchemas(nodes, rootSchema) {
  const out = []
  for (const rawNode of nodes) {
    const node = dereferenceSchema(rawNode, rootSchema)
    if (node == null || typeof node !== 'object') continue
    if (node.items) out.push(node.items)
    for (const branch of node.allOf || []) out.push(...itemSchemas([branch], rootSchema))
  }
  return out
}

function schemasAtJsonPath(jsonPath, rootSchema) {
  if (!jsonPath.startsWith('$.')) throw new Error(`unsupported stable identifier path ${jsonPath}`)
  let nodes = [rootSchema]
  for (const rawToken of jsonPath.slice(2).split('.')) {
    const isArray = rawToken.endsWith('[*]')
    const property = isArray ? rawToken.slice(0, -3) : rawToken
    nodes = propertySchemas(nodes, property, rootSchema)
    if (isArray) nodes = itemSchemas(nodes, rootSchema)
    if (nodes.length === 0) throw new Error(`stable identifier path does not resolve in schema: ${jsonPath}`)
  }
  return nodes.map((node) => dereferenceSchema(node, rootSchema))
}

function admittedIdentifierValues(jsonPath, schema) {
  const values = new Set()
  for (const node of schemasAtJsonPath(jsonPath, schema)) {
    if (Object.hasOwn(node, 'const') && typeof node.const === 'string') values.add(node.const)
    for (const value of node.enum || []) {
      if (typeof value === 'string') values.add(value)
    }
  }
  return values
}

function validateStableIdentifiers(report, schema) {
  if (!Array.isArray(report.stableIdentifiers) || report.stableIdentifiers.length === 0) {
    throw new Error(`${report.id}.stableIdentifiers must be a non-empty array`)
  }
  const paths = new Set()
  for (const group of report.stableIdentifiers) {
    requireNonEmptyString(group && group.path, `${report.id}.stableIdentifiers.path`)
    if (paths.has(group.path)) throw new Error(`${report.id} duplicates stable identifier path ${group.path}`)
    paths.add(group.path)
    if (!Array.isArray(group.values) || group.values.length === 0) throw new Error(`${report.id} ${group.path} must declare identifier values`)
    const ids = new Set()
    for (const value of group.values) {
      requireNonEmptyString(value && value.id, `${report.id} ${group.path} identifier`)
      requireNonEmptyString(value && value.meaning, `${report.id} ${group.path} ${value.id}.meaning`)
      if (ids.has(value.id)) throw new Error(`${report.id} ${group.path} duplicates identifier ${value.id}`)
      ids.add(value.id)
    }
    const admitted = admittedIdentifierValues(group.path, schema)
    if (admitted.size === 0) throw new Error(`${report.id} ${group.path} does not resolve to a schema enum/const`)
    const missing = Array.from(admitted).filter((id) => !ids.has(id)).sort()
    const extra = Array.from(ids).filter((id) => !admitted.has(id)).sort()
    if (missing.length > 0) throw new Error(`${report.id} ${group.path} omits schema identifiers: ${missing.join(', ')}`)
    if (extra.length > 0) throw new Error(`${report.id} ${group.path} declares identifiers absent from schema: ${extra.join(', ')}`)
  }
}

function compatibilitySignature(manifest, schemaDigests) {
  return {
    schemaVersion: manifest.schemaVersion,
    unknownFieldPolicy: manifest.unknownFieldPolicy,
    markdownPolicy: manifest.markdownPolicy,
    reports: manifest.reports.map((report) => ({
      id: report.id,
      filename: report.filename,
      schemaVersion: report.schemaVersion,
      schema: report.schema,
      emissionDefine: report.emissionDefine,
      schemaSha256: schemaDigests.get(report.id),
      protectedFields: report.protectedFields,
      stableIdentifiers: report.stableIdentifiers,
      deterministicOrdering: report.deterministicOrdering
    })),
    generatedArtifacts: manifest.generatedArtifacts.map((artifact) => ({
      id: artifact.id,
      publicContract: artifact.publicContract,
      protectedContract: artifact.protectedContract
    }))
  }
}

function compareCompatibility(baseline, current) {
  const errors = []
  if (baseline.unknownFieldPolicy !== current.unknownFieldPolicy) errors.push('changed unknown-field policy')
  if (baseline.markdownPolicy !== current.markdownPolicy) errors.push('changed Markdown contract policy')

  const currentReports = new Map(current.reports.map((report) => [report.id, report]))
  for (const oldReport of baseline.reports || []) {
    const report = currentReports.get(oldReport.id)
    if (report == null) {
      errors.push(`removed report contract ${oldReport.id}`)
      continue
    }
    if (report.filename !== oldReport.filename) errors.push(`changed protected report filename for ${oldReport.id}`)
    if (report.schemaVersion !== oldReport.schemaVersion) errors.push(`changed schema version in-place for ${oldReport.id}`)
    if (report.schema !== oldReport.schema) errors.push(`changed protected schema path for ${oldReport.id}`)
    if (report.emissionDefine !== oldReport.emissionDefine) errors.push(`changed report emission control for ${oldReport.id}`)
    if (report.schemaSha256 !== oldReport.schemaSha256) errors.push(`changed immutable versioned schema for ${oldReport.id}`)
    const fields = new Map((report.protectedFields || []).map((field) => [field.path, field]))
    for (const oldField of oldReport.protectedFields || []) {
      const field = fields.get(oldField.path)
      if (field == null) errors.push(`removed protected field ${oldReport.id} ${oldField.path}`)
      else if (field.type !== oldField.type) errors.push(`changed protected field type ${oldReport.id} ${oldField.path}: ${oldField.type} -> ${field.type}`)
    }
    const groups = new Map((report.stableIdentifiers || []).map((group) => [group.path, group]))
    for (const oldGroup of oldReport.stableIdentifiers || []) {
      const group = groups.get(oldGroup.path)
      if (group == null) {
        errors.push(`removed stable identifier group ${oldReport.id} ${oldGroup.path}`)
        continue
      }
      const values = new Map(group.values.map((value) => [value.id, value.meaning]))
      for (const oldValue of oldGroup.values) {
        if (!values.has(oldValue.id)) errors.push(`removed stable identifier ${oldReport.id} ${oldValue.id}`)
        else if (values.get(oldValue.id) !== oldValue.meaning) errors.push(`changed stable identifier meaning ${oldReport.id} ${oldValue.id}`)
      }
    }
    for (const ordering of oldReport.deterministicOrdering || []) {
      if (!(report.deterministicOrdering || []).includes(ordering)) errors.push(`removed deterministic-ordering promise ${oldReport.id}: ${ordering}`)
    }
  }

  const currentArtifacts = new Map(current.generatedArtifacts.map((artifact) => [artifact.id, artifact]))
  for (const oldArtifact of baseline.generatedArtifacts || []) {
    const artifact = currentArtifacts.get(oldArtifact.id)
    if (artifact == null) {
      errors.push(`removed generated-artifact contract ${oldArtifact.id}`)
      continue
    }
    if (artifact.publicContract !== oldArtifact.publicContract) errors.push(`changed generated-artifact public contract ${oldArtifact.id}`)
    for (const promise of oldArtifact.protectedContract || []) {
      if (!(artifact.protectedContract || []).includes(promise)) errors.push(`removed generated-artifact promise ${oldArtifact.id}: ${promise}`)
    }
  }
  return errors
}

function validatePublicInventory(manifest) {
  const publicManifest = readJson(publicManifestPath, 'public compatibility manifest')
  const reports = publicManifest.reports || []
  const currentReports = manifest.reports.map((report) => ({ filename: report.filename, schemaVersion: report.schemaVersion }))
  const publicReports = reports.map((report) => ({ filename: report.filename, schemaVersion: report.schemaVersion }))
  if (JSON.stringify(currentReports) !== JSON.stringify(publicReports)) throw new Error('public compatibility report inventory disagrees with generated-consumer contract')
  const artifactIds = manifest.generatedArtifacts.map((artifact) => artifact.id)
  const publicArtifactIds = (publicManifest.generatedArtifacts || []).map((artifact) => artifact.id)
  if (JSON.stringify(artifactIds) !== JSON.stringify(publicArtifactIds)) throw new Error('public compatibility artifact inventory disagrees with generated-consumer contract')
  for (const artifact of manifest.generatedArtifacts) {
    const publicEntry = publicManifest.generatedArtifacts.find((entry) => entry.id === artifact.id)
    if (publicEntry.contract !== artifact.publicContract) throw new Error(`public contract mismatch for generated artifact ${artifact.id}`)
  }
}

function loadAndValidate(manifestPath, options = {}) {
  const manifest = readJson(manifestPath, 'generated-consumer contract')
  if (manifest.schemaVersion !== 1) throw new Error('manifest.schemaVersion must be 1')
  if (manifest.compatibilityBaseline !== baselineRelativePath) throw new Error(`manifest.compatibilityBaseline must remain ${baselineRelativePath}`)
  if (manifest.unknownFieldPolicy !== 'consumers-must-ignore') throw new Error('unknownFieldPolicy must require consumers to ignore unknown fields')
  if (manifest.markdownPolicy !== 'human-only-not-machine-contract') throw new Error('markdownPolicy must keep Markdown outside the machine contract')
  if (!Array.isArray(manifest.reports) || manifest.reports.length !== 4) throw new Error('manifest.reports must contain the four admitted JSON reports')
  if (!Array.isArray(manifest.generatedArtifacts) || manifest.generatedArtifacts.length === 0) throw new Error('manifest.generatedArtifacts must be a non-empty array')

  const ajv = new Ajv({ allErrors: true, strict: true })
  const reportIds = new Set()
  const reportNames = new Set()
  const schemaDigests = new Map()
  const compilerSource = fs.readFileSync(compilerPath, 'utf8')
  for (const report of manifest.reports) {
    requireNonEmptyString(report && report.id, 'report.id')
    requireNonEmptyString(report.filename, `${report.id}.filename`)
    requireNonEmptyString(report.schema, `${report.id}.schema`)
    requireNonEmptyString(report.fixture, `${report.id}.fixture`)
    requireNonEmptyString(report.emissionDefine, `${report.id}.emissionDefine`)
    if (!Number.isInteger(report.schemaVersion) || report.schemaVersion < 1) throw new Error(`${report.id}.schemaVersion must be a positive integer`)
    if (reportIds.has(report.id)) throw new Error(`duplicate report id ${report.id}`)
    if (reportNames.has(report.filename)) throw new Error(`duplicate report filename ${report.filename}`)
    reportIds.add(report.id)
    reportNames.add(report.filename)
    const schemaPath = repoPath(report.schema, `${report.id}.schema`)
    if (!fs.existsSync(schemaPath)) throw new Error(`${report.id} schema does not exist: ${report.schema}`)
    const schema = readJson(schemaPath, `${report.id} schema`)
    validateAdditiveObjectPolicy(schema)
    let validate = null
    try {
      validate = ajv.compile(schema)
    } catch (error) {
      throw new Error(`${report.id} is not a valid JSON Schema: ${error.message}`)
    }
    if (schema.properties == null || schema.properties.schemaVersion == null || schema.properties.schemaVersion.const !== report.schemaVersion) {
      throw new Error(`${report.id} schemaVersion const disagrees with manifest`)
    }
    validateProtectedFields(report, schema)
    validateStableIdentifiers(report, schema)
    requireStringArray(report.deterministicOrdering, `${report.id}.deterministicOrdering`)
    const fixturePath = repoPath(report.fixture, `${report.id}.fixture`)
    if (!fs.existsSync(fixturePath)) throw new Error(`${report.id} fixture does not exist: ${report.fixture}`)
    const fixture = readJson(fixturePath, `${report.id} fixture`)
    if (!validate(fixture)) {
      throw new Error(`${report.id} fixture violates its schema: ${ajv.errorsText(validate.errors, { separator: '; ' })}`)
    }
    if (options.reportDir != null) {
      const emittedPath = path.join(options.reportDir, report.filename)
      if (!fs.existsSync(emittedPath)) throw new Error(`emitted report is missing: ${report.filename}`)
      const emitted = readJson(emittedPath, `emitted ${report.filename}`)
      if (!validate(emitted)) {
        throw new Error(`emitted ${report.filename} violates its schema: ${ajv.errorsText(validate.errors, { separator: '; ' })}`)
      }
    }
    schemaDigests.set(report.id, schemaDigest(schema))
    if (!compilerSource.includes(`"${report.filename}"`)) throw new Error(`compiler does not emit declared report ${report.filename}`)
    if (!compilerSource.includes(`"${report.emissionDefine}"`)) throw new Error(`compiler does not recognize ${report.emissionDefine}`)
  }

  const artifactIds = new Set()
  for (const artifact of manifest.generatedArtifacts) {
    requireNonEmptyString(artifact && artifact.id, 'generatedArtifact.id')
    requireNonEmptyString(artifact.publicContract, `${artifact.id}.publicContract`)
    if (artifactIds.has(artifact.id)) throw new Error(`duplicate generated artifact id ${artifact.id}`)
    artifactIds.add(artifact.id)
    requireStringArray(artifact.protectedContract, `${artifact.id}.protectedContract`)
    requireStringArray(artifact.evidenceFiles, `${artifact.id}.evidenceFiles`)
    requireStringArray(artifact.validationCommands, `${artifact.id}.validationCommands`)
    requireStringArray(artifact.exclusions, `${artifact.id}.exclusions`, true)
    for (const evidence of artifact.evidenceFiles) {
      const evidencePath = repoPath(evidence, `${artifact.id}.evidenceFiles`)
      if (!fs.existsSync(evidencePath)) throw new Error(`${artifact.id} evidence file does not exist: ${evidence}`)
    }
  }

  const signature = compatibilitySignature(manifest, schemaDigests)
  if (!options.skipCompatibility) {
    const baseline = readJson(defaultBaselinePath, 'generated-consumer compatibility baseline')
    const compatibilityErrors = compareCompatibility(baseline, signature)
    if (compatibilityErrors.length > 0) throw new Error(compatibilityErrors.join('\n'))
  }
  if (!options.skipPublic) validatePublicInventory(manifest)
  return { manifest, signature }
}

function argumentValue(args, name, fallback) {
  const index = args.indexOf(name)
  return index >= 0 ? args[index + 1] : fallback
}

function main() {
  const args = process.argv.slice(2)
  const manifestPath = path.resolve(argumentValue(args, '--manifest', defaultManifestPath))
  try {
    const { signature } = loadAndValidate(manifestPath, {
      skipPublic: args.includes('--skip-public'),
      skipCompatibility: args.includes('--skip-compatibility'),
      reportDir: args.includes('--report-dir') ? path.resolve(argumentValue(args, '--report-dir', '')) : null
    })
    if (args.includes('--print-signature')) {
      process.stdout.write(`${JSON.stringify(signature, null, 2)}\n`)
      return
    }
    console.log('[generated-consumer-contract] OK')
  } catch (error) {
    for (const line of String(error.message).split('\n')) console.error(`[generated-consumer-contract] ERROR: ${line}`)
    process.exit(1)
  }
}

if (require.main === module) main()

module.exports = { compareCompatibility, compatibilitySignature, loadAndValidate, schemaDigest }
