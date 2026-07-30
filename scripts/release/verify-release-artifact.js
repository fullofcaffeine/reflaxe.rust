#!/usr/bin/env node

const crypto = require('crypto')
const { execFileSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { strFromU8, unzipSync } = require('fflate')
const { compareEntryNames, validateEntryNames } = require('./deterministic-zip.js')
const {
  buildArtifacts: buildLicenseArtifacts,
  REQUIRED_COMPONENT_CONTRACT
} = require('./generate-license-artifacts.js')
const { assertPackageInputsTracked } = require('./package-input-cleanliness.js')
const {
  requireExactReflaxePaths,
  validateReflaxeHaxelib
} = require('./reflaxe-metadata.js')
const REPOSITORY_ROOT = path.join(__dirname, '..', '..')
const REQUIRED_THIRD_PARTY_COMPONENTS = [
  REQUIRED_COMPONENT_CONTRACT.reflaxe.name,
  REQUIRED_COMPONENT_CONTRACT['haxe-standard-library-derived-files'].name
]

const REQUIRED_ENTRIES = [
  'LICENSE',
  'README.md',
  'THIRD_PARTY_NOTICES.md',
  'extraParams.hxml',
  'haxelib.json',
  'release-metadata.json',
  'release-sbom.json',
  'provenance/stdlib-provenance-ledger.json',
  'runtime/hxrt/Cargo.toml',
  'src/haxe/Exception.cross.hx',
  'src/reflaxe/rust/CompilerInit.hx',
  'vendor/reflaxe/LICENSE',
  'vendor/reflaxe/provenance.json',
  'vendor/reflaxe/reflaxe-rust.patch',
  'vendor/reflaxe/src/reflaxe/ReflectCompiler.hx'
]
const ALLOWED_ROOT_FILES = new Set([
  'LICENSE',
  'README.md',
  'THIRD_PARTY_NOTICES.md',
  'Run.hx',
  'extraParams.hxml',
  'haxelib.json',
  'release-metadata.json',
  'release-sbom.json',
  'run.n'
])
const ALLOWED_ROOT_DIRECTORIES = new Set(['provenance', 'runtime', 'src', 'vendor'])

/**
 * Why
 * Correct metadata in two files does not prove that the published compiler package is complete or
 * safe. The exact ZIP approved before tagging must carry the compiler, runtime, vendored framework,
 * and source identity without traversal paths, duplicate names, symlinks, or development artifacts.
 *
 * What
 * Inspect the ZIP central directory before extraction, enforce the package layout contract, decode
 * exact metadata from the archive, and return the byte length and SHA-256 used by publication.
 *
 * How
 * A small central-directory reader exposes names, flags, methods, and Unix attributes that high-
 * level unzip maps normally hide. Only after structural validation succeeds is `fflate` used to
 * decode file contents.
 */

function findEndOfCentralDirectory(buffer) {
  const minimum = Math.max(0, buffer.length - 65_557)
  for (let offset = buffer.length - 22; offset >= minimum; offset -= 1) {
    if (buffer.readUInt32LE(offset) === 0x06054b50) return offset
  }
  throw new Error('invalid ZIP: end-of-central-directory record is missing')
}

function centralDirectoryEntries(buffer) {
  const end = findEndOfCentralDirectory(buffer)
  const count = buffer.readUInt16LE(end + 10)
  const centralSize = buffer.readUInt32LE(end + 12)
  let offset = buffer.readUInt32LE(end + 16)
  if (count === 0xffff || centralSize === 0xffffffff || offset === 0xffffffff) {
    throw new Error('ZIP64 release artifacts are not supported')
  }
  const expectedEnd = offset + centralSize
  const entries = []

  for (let index = 0; index < count; index += 1) {
    if (offset + 46 > buffer.length || buffer.readUInt32LE(offset) !== 0x02014b50) {
      throw new Error('invalid ZIP central directory')
    }
    const flags = buffer.readUInt16LE(offset + 8)
    const method = buffer.readUInt16LE(offset + 10)
    const nameLength = buffer.readUInt16LE(offset + 28)
    const extraLength = buffer.readUInt16LE(offset + 30)
    const commentLength = buffer.readUInt16LE(offset + 32)
    const externalAttributes = buffer.readUInt32LE(offset + 38)
    const nameStart = offset + 46
    const nameEnd = nameStart + nameLength
    const nameBytes = buffer.subarray(nameStart, nameEnd)
    const name = nameBytes.toString('utf8')
    if (!Buffer.from(name, 'utf8').equals(nameBytes)) throw new Error('archive entry name is not valid UTF-8')
    validateEntryNames([name])
    if ((flags & 0x1) !== 0) throw new Error(`encrypted archive entry is not allowed: ${name}`)
    if (method !== 0 && method !== 8) throw new Error(`unsupported ZIP compression method for ${name}`)
    const unixMode = externalAttributes >>> 16
    if ((unixMode & 0o170000) === 0o120000) throw new Error(`symbolic link entry is not allowed: ${name}`)
    if ((unixMode & 0o777) !== 0o644) throw new Error(`archive entry mode must be 0644: ${name}`)
    entries.push({ name, flags, method, unixMode })
    offset = nameEnd + extraLength + commentLength
  }
  if (offset !== expectedEnd) throw new Error('invalid ZIP central-directory size')
  validateEntryNames(entries.map(({ name }) => name))
  return entries
}

function parseJsonEntry(files, name) {
  try {
    return JSON.parse(strFromU8(files[name]))
  } catch (_error) {
    throw new Error(`archive entry is not readable JSON: ${name}`)
  }
}

function filesBelow(directory, prefix = '') {
  const result = []
  for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name
    if (entry.isDirectory()) result.push(...filesBelow(path.join(directory, entry.name), relative))
    else if (entry.isFile()) result.push(relative)
    else throw new Error(`unsupported source entry while verifying release: ${relative}`)
  }
  return result
}

function requireExactFile(files, archiveName, sourcePath) {
  if (!Buffer.from(files[archiveName]).equals(fs.readFileSync(sourcePath))) {
    throw new Error(`archive entry differs from the reviewed source: ${archiveName}`)
  }
}

function verifyLayout(names) {
  validateEntryNames(names)
  const sorted = [...names].sort(compareEntryNames)
  if (!names.every((name, index) => name === sorted[index])) {
    throw new Error('archive entries are not in canonical sorted order')
  }
  for (const required of REQUIRED_ENTRIES) {
    if (!names.includes(required)) throw new Error(`required archive entry is missing: ${required}`)
  }
  for (const name of names) {
    const [root, ...rest] = name.split('/')
    if (rest.length === 0) {
      if (!ALLOWED_ROOT_FILES.has(root)) throw new Error(`unexpected top-level archive entry: ${name}`)
    } else if (!ALLOWED_ROOT_DIRECTORIES.has(root)) {
      throw new Error(`unexpected archive root: ${root}`)
    }
    if (
      name.startsWith('std/') ||
      name.includes('/target/') ||
      name.includes('/node_modules/') ||
      name.includes('/.git/') ||
      name.startsWith('runtime/hxrt/tests/')
    ) {
      throw new Error(`development-only archive entry is not allowed: ${name}`)
    }
  }
}

function verifyReleaseArtifact({
  zipPath,
  canonicalZipPath,
  version,
  tag,
  sourceCommit,
  sourceRoot = REPOSITORY_ROOT,
  stdlibLedgerSourcePath = path.join(sourceRoot, 'docs', 'stdlib-provenance-ledger.json')
}) {
  if (!canonicalZipPath) {
    throw new Error('an independently rebuilt canonical package is required for release verification')
  }
  const candidateStat = fs.statSync(zipPath)
  const canonicalStat = fs.statSync(canonicalZipPath)
  if (
    fs.realpathSync(zipPath) === fs.realpathSync(canonicalZipPath) ||
    (candidateStat.dev === canonicalStat.dev && candidateStat.ino === canonicalStat.ino)
  ) {
    throw new Error('candidate and canonical package must be separate independently built files')
  }
  const bytes = fs.readFileSync(zipPath)
  const central = centralDirectoryEntries(bytes)
  const names = central.map(({ name }) => name)
  verifyLayout(names)

  let files
  try {
    files = unzipSync(bytes)
  } catch (_error) {
    throw new Error('release artifact cannot be decompressed')
  }
  const haxelib = parseJsonEntry(files, 'haxelib.json')
  const expectedHaxelib = JSON.parse(fs.readFileSync(path.join(sourceRoot, 'haxelib.json'), 'utf8'))
  delete expectedHaxelib.reflaxe
  expectedHaxelib.version = version
  expectedHaxelib.releasenote = `v${version}: See GitHub Releases`
  const sortJson = (value) => {
    if (Array.isArray(value)) return value.map(sortJson)
    if (value !== null && typeof value === 'object') {
      return Object.fromEntries(
        Object.keys(value)
          .sort()
          .map((key) => [key, sortJson(value[key])])
      )
    }
    return value
  }
  if (haxelib.version !== version) {
    throw new Error(`packaged haxelib version ${String(haxelib.version)} does not match ${version}`)
  }
  if (haxelib.releasenote !== `v${version}: See GitHub Releases`) {
    throw new Error(`packaged haxelib releasenote does not match ${version}`)
  }
  if (haxelib.classPath !== 'src') throw new Error('packaged haxelib classPath must be src')
  if (Object.prototype.hasOwnProperty.call(haxelib, 'reflaxe')) {
    throw new Error('packaged haxelib metadata still contains the source-only reflaxe block')
  }
  if (JSON.stringify(sortJson(haxelib)) !== JSON.stringify(sortJson(expectedHaxelib))) {
    throw new Error('packaged haxelib metadata differs from the reviewed source and authorized release fields')
  }

  requireExactFile(files, 'LICENSE', path.join(sourceRoot, 'LICENSE'))
  requireExactFile(files, 'README.md', path.join(sourceRoot, 'README.md'))
  requireExactFile(files, 'extraParams.hxml', path.join(sourceRoot, 'extraParams.hxml'))
  for (const optionalName of ['Run.hx', 'run.n']) {
    const sourcePath = path.join(sourceRoot, optionalName)
    const sourceHasFile = fs.existsSync(sourcePath)
    const packageHasFile = Object.prototype.hasOwnProperty.call(files, optionalName)
    if (sourceHasFile !== packageHasFile) {
      throw new Error(`optional archive entry does not match reviewed source presence: ${optionalName}`)
    }
    if (sourceHasFile) requireExactFile(files, optionalName, sourcePath)
  }
  requireExactFile(
    files,
    'provenance/stdlib-provenance-ledger.json',
    stdlibLedgerSourcePath
  )
  requireExactFile(
    files,
    'runtime/hxrt/Cargo.toml',
    path.join(sourceRoot, 'runtime', 'hxrt', 'Cargo.toml')
  )
  const vendorRoot = path.join(sourceRoot, 'vendor', 'reflaxe')
  const expectedVendorEntries = filesBelow(vendorRoot, 'vendor/reflaxe').sort(compareEntryNames)
  const packagedVendorEntries = names
    .filter((name) => name.startsWith('vendor/reflaxe/'))
    .sort(compareEntryNames)
  if (JSON.stringify(packagedVendorEntries) !== JSON.stringify(expectedVendorEntries)) {
    throw new Error('packaged Reflaxe file inventory differs from the reviewed source')
  }
  for (const archiveName of expectedVendorEntries) {
    requireExactFile(files, archiveName, path.join(sourceRoot, archiveName))
  }
  for (const [archiveName, expected] of buildLicenseArtifacts(version)) {
    if (strFromU8(files[archiveName]) !== expected) {
      throw new Error(`archive entry differs from generated license evidence: ${archiveName}`)
    }
  }

  const metadata = parseJsonEntry(files, 'release-metadata.json')
  if (metadata.schemaVersion !== 1) throw new Error('release metadata schemaVersion must be 1')
  if (metadata.version !== version) throw new Error('release metadata version does not match')
  if (metadata.tag !== tag) throw new Error('release metadata tag does not match')
  if (metadata.sourceCommit !== sourceCommit) throw new Error('release metadata source commit does not match')

  const sbom = parseJsonEntry(files, 'release-sbom.json')
  if (sbom.bomFormat !== 'CycloneDX' || sbom.specVersion !== '1.6') {
    throw new Error('release SBOM must use CycloneDX 1.6')
  }
  if (!Array.isArray(sbom.components)) throw new Error('release SBOM components must be an array')
  if (sbom.metadata?.component?.version !== version) {
    throw new Error('release SBOM package version does not match')
  }
  for (const componentName of REQUIRED_THIRD_PARTY_COMPONENTS) {
    if (!sbom.components.some((entry) => entry.name === componentName)) {
      throw new Error(`release SBOM must inventory ${componentName}`)
    }
  }

  const reflaxeProvenance = parseJsonEntry(files, 'vendor/reflaxe/provenance.json')
  requireExactReflaxePaths(reflaxeProvenance)
  if (reflaxeProvenance.schemaVersion !== 1) {
    throw new Error('vendored Reflaxe provenance schemaVersion must be 1')
  }
  if (!/^[0-9a-f]{40}$/.test(reflaxeProvenance.upstream?.baseCommit || '')) {
    throw new Error('vendored Reflaxe provenance must name an exact upstream base commit')
  }
  const patchDigest = crypto
    .createHash('sha256')
    .update(files['vendor/reflaxe/reflaxe-rust.patch'])
    .digest('hex')
  if (patchDigest !== reflaxeProvenance.localPatch?.sha256) {
    throw new Error('vendored Reflaxe patch digest does not match its provenance record')
  }
  const licenseDigest = crypto
    .createHash('sha256')
    .update(files['vendor/reflaxe/LICENSE'])
    .digest('hex')
  if (licenseDigest !== reflaxeProvenance.component?.licenseSha256) {
    throw new Error('vendored Reflaxe license digest does not match its provenance record')
  }
  validateReflaxeHaxelib(
    reflaxeProvenance,
    parseJsonEntry(files, 'vendor/reflaxe/haxelib.json')
  )
  const notices = strFromU8(files['THIRD_PARTY_NOTICES.md'])
  for (const componentName of REQUIRED_THIRD_PARTY_COMPONENTS) {
    if (!notices.includes(componentName)) {
      throw new Error(`third-party notices do not cover ${componentName}`)
    }
  }
  const componentNamed = (name) => sbom.components.find((entry) => entry.name === name)
  const reflaxeComponent = componentNamed(REQUIRED_COMPONENT_CONTRACT.reflaxe.name)
  if (
    reflaxeComponent?.version !== reflaxeProvenance.upstream.baseCommit ||
    reflaxeComponent?.licenses?.[0]?.license?.id !== reflaxeProvenance.component.license ||
    reflaxeComponent?.externalReferences?.[0]?.url !==
      reflaxeProvenance.component.upstreamRepository
  ) {
    throw new Error('release SBOM Reflaxe facts contradict the packaged provenance record')
  }
  const stdlibLedger = parseJsonEntry(files, 'provenance/stdlib-provenance-ledger.json')
  const stdlibComponent = componentNamed(
    REQUIRED_COMPONENT_CONTRACT['haxe-standard-library-derived-files'].name
  )
  if (
    stdlibComponent?.version !== stdlibLedger.upstreamStdVersion ||
    stdlibComponent?.licenses?.[0]?.license?.id !== stdlibLedger.license?.id ||
    stdlibComponent?.externalReferences?.[0]?.url !==
      `${stdlibLedger.upstreamRepository}/tree/${stdlibLedger.upstreamStdVersion}`
  ) {
    throw new Error('release SBOM Haxe facts contradict the packaged stdlib source record')
  }
  if (!notices.includes('provenance/stdlib-provenance-ledger.json')) {
    throw new Error('third-party notices do not name the packaged stdlib source record')
  }

  const canonicalBytes = fs.readFileSync(canonicalZipPath)
  if (!bytes.equals(canonicalBytes)) {
    throw new Error('release artifact differs from the independently rebuilt canonical package')
  }

  return {
    entries: names,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
    size: bytes.length
  }
}

function parseArgs(argv) {
  const values = {}
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index]
    const value = argv[index + 1]
    if (!flag || !flag.startsWith('--') || value === undefined) throw new Error('invalid verifier arguments')
    values[flag.slice(2)] = value
  }
  for (const required of ['zip', 'version', 'tag', 'source-sha']) {
    if (!values[required]) throw new Error(`--${required} is required`)
  }
  return values
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  const sourceCommit = execFileSync('git', ['rev-parse', 'HEAD^{commit}'], {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8'
  }).trim()
  if (sourceCommit !== args['source-sha']) {
    throw new Error('reviewed source commit does not match the checked-out commit')
  }
  const trackedChanges = execFileSync(
    'git',
    ['status', '--porcelain', '--untracked-files=no'],
    { cwd: REPOSITORY_ROOT, encoding: 'utf8' }
  )
  if (trackedChanges.trim()) {
    throw new Error('reviewed source contains tracked changes')
  }
  assertPackageInputsTracked(REPOSITORY_ROOT)

  const canonicalRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-release-verify-'))
  const canonicalZipPath = path.join(canonicalRoot, 'reflaxe.rust.zip')
  try {
    execFileSync(
      'bash',
      [
        'scripts/release/package-haxelib.sh',
        canonicalZipPath,
        args.version,
        args.tag,
        sourceCommit
      ],
      { cwd: REPOSITORY_ROOT, stdio: 'inherit' }
    )
    const result = verifyReleaseArtifact({
      zipPath: path.resolve(args.zip),
      canonicalZipPath,
      version: args.version,
      tag: args.tag,
      sourceCommit
    })
    console.log(JSON.stringify(result))
  } finally {
    fs.rmSync(canonicalRoot, { recursive: true, force: true })
  }
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[release-artifact] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = { centralDirectoryEntries, verifyLayout, verifyReleaseArtifact }
