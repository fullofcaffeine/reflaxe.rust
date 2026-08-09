#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const crypto = require('crypto')
const { requireExactReflaxePaths } = require('./reflaxe-metadata.js')

const root = path.resolve(__dirname, '..', '..')
const REQUIRED_COMPONENT_IDS = ['reflaxe-rust', 'reflaxe', 'haxe-standard-library-derived-files']
const STDLIB_PACKAGE_EVIDENCE_PATH = 'provenance/stdlib-provenance-ledger.json'
const REFLAXE_PROVENANCE_PATH = 'vendor/reflaxe/provenance.json'
const STDLIB_PROVENANCE_PATH = 'docs/stdlib-provenance-ledger.json'
const STDLIB_LICENSE_SOURCE_PATH = 'docs/licenses/haxe-stdlib-4.3.7-MIT.txt'
const PROJECT_COMPONENT_ID = 'reflaxe-rust'
const PROJECT_NAME = 'reflaxe.rust'
const PROJECT_REPOSITORY = 'https://github.com/fullofcaffeine/reflaxe.rust'
const REQUIRED_COMPONENT_CONTRACT = Object.freeze({
  'reflaxe-rust': {
    name: 'reflaxe.rust',
    kind: 'application',
    versionSource: 'haxelib.json',
    licenseSource: 'haxelib.json',
    licenseFile: 'LICENSE',
    source: 'https://github.com/fullofcaffeine/reflaxe.rust'
  },
  reflaxe: {
    name: 'Reflaxe',
    kind: 'library',
    provenanceFile: REFLAXE_PROVENANCE_PATH
  },
  'haxe-standard-library-derived-files': {
    name: 'Haxe Standard Library derived files',
    kind: 'library',
    stdlibProvenanceFile: STDLIB_PROVENANCE_PATH
  }
})

function validateRequiredComponentIds(source) {
  if (!Array.isArray(source.components)) throw new Error('release component inventory must be an array')
  const ids = source.components.map((component) => component.id)
  if (new Set(ids).size !== ids.length) throw new Error('release component inventory contains duplicate IDs')
  for (const id of REQUIRED_COMPONENT_IDS) {
    if (!ids.includes(id)) throw new Error(`release component inventory is missing required component: ${id}`)
    const component = source.components.find((entry) => entry.id === id)
    const contract = REQUIRED_COMPONENT_CONTRACT[id]
    for (const [field, expected] of Object.entries(contract)) {
      if (component[field] !== expected) {
        throw new Error(`release component ${id} ${field} must be exactly ${expected}`)
      }
    }
    const forbiddenLicenseOverrides = id === PROJECT_COMPONENT_ID
      ? ['licenseText', 'licenseSourceFile', 'licenseSha256']
      : ['license', 'licenseText', 'licenseSourceFile', 'licenseFile', 'licenseSha256']
    if (forbiddenLicenseOverrides.some((field) => Object.prototype.hasOwnProperty.call(component, field))) {
      throw new Error(`release component ${id} must not override reviewed license bytes`)
    }
    const matchingNames = source.components.filter((entry) => entry.name === contract.name)
    if (matchingNames.length !== 1) {
      throw new Error(`release component inventory must contain exactly one ${contract.name} component`)
    }
  }
  const stdlib = source.components.find(
    (component) => component.id === 'haxe-standard-library-derived-files'
  )
  if (!stdlib.notice?.includes(STDLIB_PACKAGE_EVIDENCE_PATH)) {
    throw new Error('stdlib release notice must name the package-local source record')
  }
  if (/(?:https?:)?\/\//i.test(stdlib.notice)) {
    throw new Error('stdlib release notice must not depend on an external branch URL')
  }
  for (const component of source.components.filter((entry) => !REQUIRED_COMPONENT_IDS.includes(entry.id))) {
    if (
      ['licenseSourceFile', 'licenseFile', 'licenseSha256'].some((field) =>
        Object.prototype.hasOwnProperty.call(component, field)
      )
    ) {
      throw new Error(
        'extra release component license text must be inline in the reviewed component record'
      )
    }
    if (typeof component.licenseText !== 'string' || component.licenseText.trim().length === 0) {
      throw new Error(
        'extra release component license text must be inline in the reviewed component record'
      )
    }
  }
}

function normalizeRepository(value) {
  if (typeof value !== 'string') return ''
  return value.trim().replace(/\/+$/, '').replace(/\.git$/, '')
}

/**
 * Why
 * `haxelib.json` is the installer-facing product identity. A deterministic SBOM is still false if
 * both generated packages call themselves a different product while the SBOM says reflaxe.rust.
 *
 * What
 * Require the reviewed Haxelib metadata to identify this project and carry a non-empty license.
 *
 * How
 * Compare the name and normalized repository with code-owned product facts. The exact license ID is
 * intentionally not fixed here; legal policy owns that choice, while generation and verification
 * require the package and SBOM to use the same non-empty value.
 */
function validateProjectHaxelib(haxelib) {
  if (haxelib?.name !== PROJECT_NAME) {
    throw new Error(`reviewed ${PROJECT_NAME} Haxelib metadata name must be exactly ${PROJECT_NAME}`)
  }
  if (normalizeRepository(haxelib?.url) !== normalizeRepository(PROJECT_REPOSITORY)) {
    throw new Error(`reviewed ${PROJECT_NAME} Haxelib metadata repository must be exactly ${PROJECT_REPOSITORY}`)
  }
  if (typeof haxelib?.license !== 'string' || haxelib.license.trim().length === 0) {
    throw new Error(`reviewed ${PROJECT_NAME} Haxelib metadata license must be a non-empty string`)
  }
}

function parseArgs(args) {
  const values = {
    'output-dir': root,
    version: JSON.parse(fs.readFileSync(path.join(root, 'haxelib.json'))).version,
    check: false
  }
  for (let index = 0; index < args.length; ) {
    const key = args[index]
    if (key === '--check') {
      values.check = true
      index += 1
      continue
    }
    const value = args[index + 1]
    if (!key?.startsWith('--') || value === undefined) throw new Error('expected --output-dir and --version values')
    values[key.slice(2)] = value
    index += 2
  }
  return values
}

function stripTomlComment(line) {
  let quote = null
  let escaped = false
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index]
    if (quote === '"' && escaped) {
      escaped = false
      continue
    }
    if (quote === '"' && character === '\\') {
      escaped = true
      continue
    }
    if (quote !== null) {
      if (character === quote) quote = null
      continue
    }
    if (character === '"' || character === "'") quote = character
    else if (character === '#') return line.slice(0, index)
  }
  return line
}

function splitTomlEntries(value) {
  const entries = []
  let start = 0
  let quote = null
  let escaped = false
  let square = 0
  let curly = 0
  for (let index = 0; index < value.length; index += 1) {
    const character = value[index]
    if (quote === '"' && escaped) {
      escaped = false
      continue
    }
    if (quote === '"' && character === '\\') {
      escaped = true
      continue
    }
    if (quote !== null) {
      if (character === quote) quote = null
      continue
    }
    if (character === '"' || character === "'") quote = character
    else if (character === '[') square += 1
    else if (character === ']') square -= 1
    else if (character === '{') curly += 1
    else if (character === '}') curly -= 1
    else if (character === ',' && square === 0 && curly === 0) {
      entries.push(value.slice(start, index).trim())
      start = index + 1
    }
  }
  entries.push(value.slice(start).trim())
  return entries.filter(Boolean)
}

function tomlString(value, label) {
  const trimmed = value.trim()
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    try {
      return JSON.parse(trimmed)
    } catch (_error) {
      throw new Error(`Cargo manifest contains an invalid ${label} string`)
    }
  }
  if (trimmed.startsWith("'") && trimmed.endsWith("'")) return trimmed.slice(1, -1)
  throw new Error(`Cargo manifest ${label} must be a string`)
}

function tomlBoolean(value, label) {
  const trimmed = value.trim()
  if (trimmed !== 'true' && trimmed !== 'false') {
    throw new Error(`Cargo manifest ${label} must be boolean`)
  }
  return trimmed === 'true'
}

function tomlStringArray(value, label) {
  const trimmed = value.trim()
  if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
    throw new Error(`Cargo manifest ${label} must be an array of strings`)
  }
  for (const entry of splitTomlEntries(trimmed.slice(1, -1))) tomlString(entry, label)
}

function unsupportedDependencyField(label, key) {
  throw new Error(`Cargo manifest ${label}.${key} uses an unsupported Cargo dependency field`)
}

function normalizedTomlAuthorityPath(value) {
  return value.replace(/["'\s]/g, '')
}

function isCargoSourceOverridePath(value) {
  return /^(patch(?:\.|$)|replace(?:\.|$)|workspace\.dependencies(?:\.|$))/.test(
    normalizedTomlAuthorityPath(value)
  )
}

function cargoVersionRequirement(value) {
  return /^(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*)){0,2}(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/.test(value)
    ? `^${value}`
    : value
}

function dependencyValue(value, label) {
  const trimmed = value.trim()
  if (trimmed.startsWith('"') || trimmed.startsWith("'")) {
    return { version: tomlString(trimmed, label) }
  }
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
    throw new Error(`Cargo manifest ${label} must be a version string or inline table`)
  }
  const fields = {}
  for (const entry of splitTomlEntries(trimmed.slice(1, -1))) {
    const equals = entry.indexOf('=')
    if (equals < 1) throw new Error(`Cargo manifest contains malformed ${label} metadata`)
    const key = entry.slice(0, equals).trim()
    const fieldValue = entry.slice(equals + 1).trim()
    if (key === 'version' || key === 'package') fields[key] = tomlString(fieldValue, `${label}.${key}`)
    else if (key === 'optional') fields.optional = tomlBoolean(fieldValue, `${label}.optional`)
    else if (key === 'default-features') tomlBoolean(fieldValue, `${label}.default-features`)
    else if (key === 'features') tomlStringArray(fieldValue, `${label}.features`)
    else unsupportedDependencyField(label, key)
  }
  return fields
}

function dependencyTableField(key, value, label) {
  if (key === 'version' || key === 'package') return { [key]: tomlString(value, `${label}.${key}`) }
  if (key === 'optional') return { optional: tomlBoolean(value, `${label}.optional`) }
  if (key === 'default-features') {
    tomlBoolean(value, `${label}.default-features`)
    return {}
  }
  if (key === 'features') {
    tomlStringArray(value, `${label}.features`)
    return {}
  }
  return unsupportedDependencyField(label, key)
}

function dependencySection(header) {
  const direct = /^(dependencies|dev-dependencies|build-dependencies)$/.exec(header)
  if (direct) return { kind: direct[1], localName: null, target: null }
  const table = /^(dependencies|dev-dependencies|build-dependencies)\.([A-Za-z0-9_-]+)$/.exec(header)
  if (table) return { kind: table[1], localName: table[2], target: null }
  const targeted = /^target\.([^.]+)\.(dependencies|dev-dependencies|build-dependencies)(?:\.([A-Za-z0-9_-]+))?$/.exec(header)
  if (targeted) {
    return {
      kind: targeted[2],
      localName: targeted[3] || null,
      target: targeted[1]
    }
  }
  return null
}

/**
 * Why
 * The release inventory describes unresolved requirements written in the reviewed Cargo manifest.
 * Executing an ambient `cargo metadata` lets caller PATH, HOME, config, and toolchain state rewrite
 * those facts while two builds still agree.
 *
 * What
 * Read only dependency declarations from the source-owned Cargo.toml and return the same closed
 * requirement shape consumed by notice and SBOM generation.
 *
 * How
 * A deliberately small fail-closed TOML reader accepts Cargo dependency tables, target-specific
 * tables, version strings, and inline tables. Unsupported dependency syntax is rejected rather than
 * delegated to a process outside the reviewed source boundary.
 */
function cargoRequirements(cargoPath = path.join(root, 'runtime', 'hxrt', 'Cargo.toml')) {
  const source = fs.readFileSync(path.resolve(cargoPath), 'utf8')
  const requirements = new Map()
  let section = null
  for (const rawLine of source.split(/\r?\n/)) {
    const line = stripTomlComment(rawLine).trim()
    if (!line) continue
    if (line.startsWith('[') && line.endsWith(']')) {
      const header = line.slice(1, -1).trim()
      if (header.includes('\\')) {
        throw new Error('Cargo manifest uses an unsupported escaped TOML key path')
      }
      if (isCargoSourceOverridePath(header)) {
        throw new Error(`Cargo manifest uses unsupported Cargo source override section [${header}]`)
      }
      const normalizedHeader = normalizedTomlAuthorityPath(header)
      section = dependencySection(normalizedHeader)
      if (
        !section &&
        /^(dependencies|dev-dependencies|build-dependencies)(?:\.|$)|^target\./.test(normalizedHeader)
      ) {
        throw new Error(`Cargo manifest uses an unsupported dependency table [${header}]`)
      }
      continue
    }
    const topLevelKey = line.slice(0, line.indexOf('=') < 0 ? line.length : line.indexOf('='))
    if (!section && topLevelKey.includes('\\')) {
      throw new Error('Cargo manifest uses an unsupported escaped TOML key path')
    }
    if (!section && isCargoSourceOverridePath(topLevelKey)) {
      throw new Error('Cargo manifest uses an unsupported top-level Cargo source override')
    }
    if (
      !section &&
      /^(dependencies|dev-dependencies|build-dependencies)(?:\.|$)|^target\./.test(
        normalizedTomlAuthorityPath(topLevelKey)
      )
    ) {
      throw new Error('unsupported Cargo top-level dotted dependency declaration')
    }
    if (!section) continue
    const equals = line.indexOf('=')
    if (equals < 1) throw new Error('Cargo dependency declaration is malformed')
    const key = line.slice(0, equals).trim()
    if (!/^[A-Za-z0-9_-]+$/.test(key)) throw new Error('Cargo dependency name is malformed')
    const localName = section.localName || key
    const fields = section.localName
      ? dependencyTableField(key, line.slice(equals + 1), localName)
      : dependencyValue(line.slice(equals + 1), localName)
    const identity = [section.target || '', section.kind, localName].join('\0')
    const current = requirements.get(identity) || {
      name: localName,
      localName,
      requirement: null,
      optional: false,
      kind: section.kind === 'dependencies' ? 'runtime' : section.kind.replace('-dependencies', ''),
      target: section.target
    }
    if (fields.package) current.name = fields.package
    if (fields.version) current.requirement = cargoVersionRequirement(fields.version)
    if (fields.optional !== undefined) current.optional = fields.optional
    requirements.set(identity, current)
  }
  const result = [...requirements.values()]
  for (const requirement of result) {
    if (!requirement.requirement) {
      throw new Error(`Cargo dependency ${requirement.localName} lacks a reviewed version requirement`)
    }
  }
  return result.sort((left, right) =>
    [left.localName, left.name, left.kind, left.target || ''].join('\0').localeCompare(
      [right.localName, right.name, right.kind, right.target || ''].join('\0')
    )
  )
}

function sha256Text(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function resolveStdlibComponent(component, ledger) {
  if (!ledger.upstreamStdVersion || !ledger.upstreamRepository || !ledger.license?.id) {
    throw new Error('stdlib provenance ledger lacks version, repository, or license facts')
  }
  if (ledger.license.sourceFile !== STDLIB_LICENSE_SOURCE_PATH) {
    throw new Error(`stdlib license sourceFile must be exactly ${STDLIB_LICENSE_SOURCE_PATH}`)
  }
  return {
    ...component,
    version: ledger.upstreamStdVersion,
    license: ledger.license.id,
    licenseSourceFile: ledger.license.sourceFile,
    licenseSha256: ledger.license.sha256,
    source: `${ledger.upstreamRepository}/tree/${ledger.upstreamStdVersion}`
  }
}

function resolvedComponents(source) {
  const haxelib = JSON.parse(fs.readFileSync(path.join(root, 'haxelib.json'), 'utf8'))
  validateProjectHaxelib(haxelib)
  return source.components.map((component) => {
    const withPackageFacts = {
      ...component,
      ...(component.licenseSource === 'haxelib.json' ? { license: haxelib.license } : {})
    }
    if (component.id === 'haxe-standard-library-derived-files') {
      const ledger = JSON.parse(fs.readFileSync(path.join(root, STDLIB_PROVENANCE_PATH), 'utf8'))
      return resolveStdlibComponent(withPackageFacts, ledger)
    }
    if (component.id !== 'reflaxe') return withPackageFacts
    const provenancePath = path.join(root, REFLAXE_PROVENANCE_PATH)
    const provenance = JSON.parse(fs.readFileSync(provenancePath, 'utf8'))
    requireExactReflaxePaths(provenance)
    return {
      ...withPackageFacts,
      version: provenance.upstream.baseCommit,
      license: provenance.component.license,
      licenseFile: 'vendor/reflaxe/LICENSE',
      licenseSha256: provenance.component.licenseSha256,
      source: provenance.component.upstreamRepository
    }
  })
}

/**
 * Validate every license byte source before notice generation reads it.
 *
 * The component facts may describe the expected digest, but they do not grant filesystem access.
 * Paths must stay normalized and inside this checkout, and the final path must be a regular file
 * rather than a symlink to bytes that are absent from the reviewed Git tree. Release preflight then
 * independently proves that the same path is stored as a regular Git blob.
 */
function validateLicenseFiles(components) {
  for (const component of components) {
    const licenseSourceFile = component.licenseSourceFile || component.licenseFile
    if (!licenseSourceFile || !component.licenseSha256) continue
    if (
      path.isAbsolute(licenseSourceFile) ||
      /^[A-Za-z]:/.test(licenseSourceFile) ||
      licenseSourceFile.includes('\\') ||
      path.posix.normalize(licenseSourceFile) !== licenseSourceFile ||
      licenseSourceFile.split('/').some((segment) => segment === '.' || segment === '..' || segment === '')
    ) {
      throw new Error(`license source path is not a normalized repository-relative file: ${licenseSourceFile}`)
    }
    const licensePath = path.resolve(root, ...licenseSourceFile.split('/'))
    const rootPrefix = `${fs.realpathSync(root)}${path.sep}`
    if (!licensePath.startsWith(rootPrefix)) {
      throw new Error(`license source is outside the reviewed repository: ${licenseSourceFile}`)
    }
    if (!fs.existsSync(licensePath)) throw new Error(`license source is missing: ${licenseSourceFile}`)
    if (!fs.lstatSync(licensePath).isFile()) {
      throw new Error(`license source must be a regular reviewed file: ${licenseSourceFile}`)
    }
    if (!fs.realpathSync(licensePath).startsWith(rootPrefix)) {
      throw new Error(`license source resolves outside the reviewed repository: ${licenseSourceFile}`)
    }
    if (sha256Text(fs.readFileSync(licensePath)) !== component.licenseSha256) {
      throw new Error(`license source digest is stale: ${licenseSourceFile}`)
    }
  }
}

function notice(components, cargoPolicy) {
  const sections = components
    .filter((component) => component.id !== 'reflaxe-rust')
    .map((component) => {
      const details = [
        `License: ${component.license}`,
        `Source: ${component.source}`,
        component.copyright,
        component.notice,
        component.id === 'haxe-standard-library-derived-files'
          ? fs.readFileSync(path.join(root, STDLIB_LICENSE_SOURCE_PATH), 'utf8').trim()
          : component.id === 'reflaxe'
            ? fs.readFileSync(path.join(root, 'vendor', 'reflaxe', 'LICENSE'), 'utf8').trim()
            : component.licenseText,
        component.licenseFile ? `License text: ${component.licenseFile}` : null
      ].filter(Boolean)
      return `## ${component.name}\n\n${details.join('\n\n')}`
    })
  return `# Third-party notices

This file lists source code included in the reflaxe.rust release package. It is
an inventory for reviewers and does not replace professional legal advice.

${sections.join('\n\n')}

## Rust crate dependencies

${cargoPolicy.explanation} The declared requirements are inventoried in
\`release-sbom.json\`; exact resolved dependency licenses belong to the
application's reviewed lockfile and release process.
`
}

function componentToCyclone(component, version) {
  const actualVersion = component.versionSource ? version : component.version
  return {
    type: component.kind,
    'bom-ref': `pkg:generic/${component.id}@${actualVersion}`,
    name: component.name,
    version: actualVersion,
    licenses: [{ license: { id: component.license } }],
    externalReferences: [{ type: 'vcs', url: component.source }],
    properties: [
      ...(component.licenseFile ? [{ name: 'reflaxe.rust:license-file', value: component.licenseFile }] : []),
      ...(component.notice ? [{ name: 'reflaxe.rust:notice', value: component.notice }] : [])
    ]
  }
}

function buildArtifacts(version, source = null) {
  source = source || JSON.parse(fs.readFileSync(path.join(root, 'docs', 'release-package-components.json'), 'utf8'))
  validateRequiredComponentIds(source)
  const releaseComponents = resolvedComponents(source)
  validateLicenseFiles(releaseComponents)
  const dependencies = cargoRequirements().map((dependency) => {
    const identity = JSON.stringify([
      dependency.localName,
      dependency.name,
      dependency.requirement,
      dependency.kind,
      dependency.target
    ])
    return {
      type: 'library',
      'bom-ref': `urn:reflaxe-rust:cargo-requirement:${sha256Text(identity).slice(0, 32)}`,
      name: dependency.name,
      scope: dependency.kind === 'dev' ? 'excluded' : dependency.optional ? 'optional' : 'required',
      externalReferences: [{ type: 'distribution', url: `https://crates.io/crates/${dependency.name}` }],
      properties: [
        { name: 'reflaxe.rust:inventory-scope', value: source.cargoDependencyPolicy.scope },
        { name: 'reflaxe.rust:dependency-kind', value: dependency.kind },
        { name: 'reflaxe.rust:local-dependency-name', value: dependency.localName },
        { name: 'reflaxe.rust:version-requirement', value: dependency.requirement },
        { name: 'reflaxe.rust:version-kind', value: 'unresolved Cargo requirement' },
        ...(dependency.target ? [{ name: 'reflaxe.rust:target-condition', value: dependency.target }] : [])
      ]
    }
  })
  const components = releaseComponents.map((component) => componentToCyclone(component, version))
  const primaryIndex = releaseComponents.findIndex((component) => component.id === PROJECT_COMPONENT_ID)
  if (primaryIndex < 0) throw new Error(`release component inventory is missing required component: ${PROJECT_COMPONENT_ID}`)
  const primary = components[primaryIndex]
  const included = components.filter((_component, index) => index !== primaryIndex)
  const sbom = {
    $schema: 'https://cyclonedx.org/schema/bom-1.6.schema.json',
    bomFormat: 'CycloneDX',
    specVersion: '1.6',
    version: 1,
    metadata: { component: primary },
    components: [...included, ...dependencies],
    dependencies: [
      {
        ref: primary['bom-ref'],
        dependsOn: [...included, ...dependencies].map((component) => component['bom-ref'])
      },
      ...[...included, ...dependencies].map((component) => ({
        ref: component['bom-ref'],
        dependsOn: []
      }))
    ]
  }
  return new Map([
    ['THIRD_PARTY_NOTICES.md', notice(releaseComponents, source.cargoDependencyPolicy)],
    ['release-sbom.json', `${JSON.stringify(sbom, null, 2)}\n`]
  ])
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  const outputDir = path.resolve(args['output-dir'])
  const outputs = buildArtifacts(args.version)
  fs.mkdirSync(outputDir, { recursive: true })
  for (const [name, content] of outputs) {
    const target = path.join(outputDir, name)
    if (args.check) {
      if (!fs.existsSync(target) || fs.readFileSync(target, 'utf8') !== content) {
        throw new Error(`${name} is stale; run npm run docs:license-artifacts`)
      }
    } else {
      fs.writeFileSync(target, content)
    }
  }
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[license-artifacts] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = {
  buildArtifacts,
  cargoRequirements,
  validateRequiredComponentIds,
  resolveStdlibComponent,
  REQUIRED_COMPONENT_IDS,
  REQUIRED_COMPONENT_CONTRACT,
  REFLAXE_PROVENANCE_PATH,
  STDLIB_PROVENANCE_PATH,
  STDLIB_PACKAGE_EVIDENCE_PATH,
  STDLIB_LICENSE_SOURCE_PATH,
  PROJECT_COMPONENT_ID,
  PROJECT_NAME,
  PROJECT_REPOSITORY,
  validateProjectHaxelib
}
