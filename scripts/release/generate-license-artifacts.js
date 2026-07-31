#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const crypto = require('crypto')
const { execFileSync } = require('child_process')
const { requireExactReflaxePaths } = require('./reflaxe-metadata.js')

const root = path.resolve(__dirname, '..', '..')
const REQUIRED_COMPONENT_IDS = ['reflaxe-rust', 'reflaxe', 'haxe-standard-library-derived-files']
const STDLIB_PACKAGE_EVIDENCE_PATH = 'provenance/stdlib-provenance-ledger.json'
const REFLAXE_PROVENANCE_PATH = 'vendor/reflaxe/provenance.json'
const STDLIB_PROVENANCE_PATH = 'docs/stdlib-provenance-ledger.json'
const STDLIB_LICENSE_SOURCE_PATH = 'docs/licenses/haxe-stdlib-4.3.7-MIT.txt'
const PROJECT_COMPONENT_ID = 'reflaxe-rust'
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

function cargoRequirements(cargoPath = path.join(root, 'runtime', 'hxrt', 'Cargo.toml')) {
  cargoPath = path.resolve(cargoPath)
  const cargo = process.env.CARGO_BIN || 'cargo'
  const metadata = JSON.parse(
    execFileSync(cargo, ['metadata', '--format-version', '1', '--no-deps', '--manifest-path', cargoPath], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    })
  )
  const hxrt = metadata.packages.find((entry) => entry.manifest_path === cargoPath)
  if (!hxrt) throw new Error('Cargo metadata did not return the hxrt package')
  return hxrt.dependencies
    .map((dependency) => ({
      name: dependency.name,
      localName: dependency.rename || dependency.name,
      requirement: dependency.req,
      optional: dependency.optional,
      kind: dependency.kind || 'runtime',
      target: dependency.target || null
    }))
    .sort((left, right) =>
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
        component.licenseText ||
          ((component.licenseSourceFile || component.licenseFile) && component.licenseSha256
            ? fs
                .readFileSync(path.join(root, component.licenseSourceFile || component.licenseFile), 'utf8')
                .trim()
            : null),
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
  PROJECT_COMPONENT_ID
}
