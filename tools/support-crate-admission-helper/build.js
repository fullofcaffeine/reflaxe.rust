#!/usr/bin/env node

const assert = require('node:assert/strict')
const crypto = require('node:crypto')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const helperRoot = __dirname
const repoRoot = path.resolve(helperRoot, '..', '..')
if (Object.prototype.hasOwnProperty.call(process.env, 'HAXE_BIN')) {
  throw new Error('HAXE_BIN is not admitted for the support-crate helper package build')
}
const haxeShim = path.join(
  repoRoot,
  'node_modules',
  '.bin',
  process.platform === 'win32' ? 'haxe.cmd' : 'haxe'
)
const cargo = process.env.CARGO_BIN || 'cargo'
const rustc = process.env.RUSTC_BIN || 'rustc'
const host = `${process.platform}-${process.arch}`
const packagePlatform = new Map([
  ['darwin-arm64', 'darwin-arm64']
]).get(host)
const cargoTarget = 'aarch64-apple-darwin'
const check = process.argv.includes('--check')
const allowedArguments = new Set(['--check'])

for (const argument of process.argv.slice(2)) {
  if (!allowedArguments.has(argument)) throw new Error(`unknown argument: ${argument}`)
}
if (packagePlatform === undefined) {
  throw new Error(`support-crate admission helper does not support build host ${host}`)
}

const outputRoot = path.join(helperRoot, check ? 'out_verify' : 'out')
const packagedDirectory = path.join(repoRoot, 'native', 'support-crate-admission', packagePlatform)
const packagedBinary = path.join(packagedDirectory, 'hxrs-support-crate-admission')
const inventoryPath = path.join(packagedDirectory, 'dependency-inventory.json')
const provenancePath = path.join(packagedDirectory, 'binary-provenance.json')
const noticesPath = path.join(packagedDirectory, 'THIRD_PARTY_NOTICES.md')
const cargoVendorConfig = path.join(helperRoot, 'cargo-vendor-config.toml')

function utf8Compare(left, right) {
  return Buffer.compare(Buffer.from(left, 'utf8'), Buffer.from(right, 'utf8'))
}

function resolveExecutable(command) {
  const candidates = command.includes(path.sep)
    ? [path.resolve(command)]
    : (process.env.PATH || '').split(path.delimiter).map(directory => path.join(directory, command))
  for (const candidate of candidates) {
    try {
      fs.accessSync(candidate, fs.constants.X_OK)
      return fs.realpathSync(candidate)
    } catch (_) {}
  }
  throw new Error(`cannot resolve executable: ${command}`)
}

const resolvedCargo = resolveExecutable(cargo)
const resolvedRustc = resolveExecutable(rustc)
const resolvedHaxeShim = resolveExecutable(haxeShim)
const xcrun = resolveExecutable('xcrun')

const haxeScope = JSON.parse(fs.readFileSync(path.join(repoRoot, '.haxerc'), 'utf8'))
if (typeof haxeScope.version !== 'string' || haxeScope.resolveLibs !== 'scoped') {
  throw new Error('the package build requires one exact scoped Haxe version in .haxerc')
}
const resolvedHaxeCompiler = resolveExecutable(path.join(
  os.homedir(),
  'haxe',
  'versions',
  haxeScope.version,
  process.platform === 'win32' ? 'haxe.exe' : 'haxe'
))
const haxeStdRoot = path.join(path.dirname(resolvedHaxeCompiler), 'std')
if (!fs.statSync(haxeStdRoot).isDirectory()) {
  throw new Error(`selected Haxe ${haxeScope.version} omits its standard library`)
}

function run(command, args, cwd = repoRoot, env = process.env) {
  const result = spawnSync(command, args, { cwd, encoding: 'utf8', env })
  assert.ifError(result.error)
  if (result.status !== 0) {
    throw new Error(`${command} failed:\n${result.stdout || ''}${result.stderr || ''}`)
  }
  return result.stdout.trim()
}

const sdkRoot = run(xcrun, ['--sdk', 'macosx', '--show-sdk-path'])
const sdkVersion = run(xcrun, ['--sdk', 'macosx', '--show-sdk-version'])
const sdkSettings = path.join(sdkRoot, 'SDKSettings.json')
if (!fs.existsSync(sdkSettings)) throw new Error('selected macOS SDK omits SDKSettings.json')
const linker = fs.realpathSync(run(xcrun, ['--sdk', 'macosx', '--find', 'clang']))
const cargoHome = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-support-cargo-home-'))
process.on('exit', () => fs.rmSync(cargoHome, { recursive: true, force: true }))
const admittedRepositoryConfig = path.join(repoRoot, '.cargo', 'config.toml')
for (let current = repoRoot; ; current = path.dirname(current)) {
  for (const name of ['config', 'config.toml']) {
    const config = path.join(current, '.cargo', name)
    if (fs.existsSync(config) && config !== admittedRepositoryConfig) {
      throw new Error(`ancestor Cargo configuration is not admitted for the package build: ${config}`)
    }
  }
  if (path.dirname(current) === current) break
}
const cargoEnvironment = {
  PATH: process.env.PATH || '',
  HOME: process.env.HOME,
  TMPDIR: process.env.TMPDIR || os.tmpdir(),
  LANG: 'C',
  LC_ALL: 'C',
  CARGO_HOME: cargoHome,
  CARGO_INCREMENTAL: '0',
  CARGO_NET_OFFLINE: 'true',
  RUSTC: resolvedRustc,
  RUSTFLAGS: '',
  CARGO_ENCODED_RUSTFLAGS: '',
  SDKROOT: sdkRoot,
  MACOSX_DEPLOYMENT_TARGET: '11.0',
  CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER: linker,
  SOURCE_DATE_EPOCH: '0',
  ZERO_AR_DATE: '1'
}
const haxeEnvironment = {
  PATH: [path.dirname(process.execPath), '/usr/bin', '/bin', '/usr/sbin', '/sbin'].join(path.delimiter),
  HOME: os.homedir(),
  TMPDIR: process.env.TMPDIR || os.tmpdir(),
  LANG: 'C',
  LC_ALL: 'C'
}
const haxeScopeArguments = ['--cwd', repoRoot]

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex')
}

function canonicalJson(value) {
  return `${JSON.stringify(value, null, 2)}\n`
}

function walkFiles(root) {
  const result = []
  const visit = absolute => {
    const stat = fs.lstatSync(absolute)
    if (stat.isSymbolicLink()) throw new Error(`source input is a symbolic link: ${path.relative(repoRoot, absolute)}`)
    if (stat.isDirectory()) {
      for (const name of fs.readdirSync(absolute).sort()) visit(path.join(absolute, name))
    } else if (stat.isFile()) {
      result.push(absolute)
    } else {
      throw new Error(`source input is not a regular file: ${path.relative(repoRoot, absolute)}`)
    }
  }
  visit(root)
  return result
}

function appendDigestFile(digest, logicalPath, file) {
  const bytes = fs.readFileSync(file)
  digest.update(Buffer.from(`${Buffer.byteLength(logicalPath)}:${logicalPath}:${bytes.length}:`, 'utf8'))
  digest.update(bytes)
}

function treeIdentity(root, logicalRoot) {
  const files = walkFiles(root).sort((left, right) => utf8Compare(
    path.relative(root, left),
    path.relative(root, right)
  ))
  const digest = crypto.createHash('sha256')
  for (const file of files) {
    const relative = path.relative(root, file).split(path.sep).join('/')
    appendDigestFile(digest, `${logicalRoot}/${relative}`, file)
  }
  return { fileCount: files.length, sha256: digest.digest('hex') }
}

function sourceInputIdentity() {
  const roots = [
    'src',
    'std',
    'runtime',
    'vendor/reflaxe',
    'haxe_libraries',
    'tools/support-crate-admission-helper/src',
    'tools/support-crate-admission-helper/native',
    'tools/support-crate-admission-helper/compile.hxml',
    'tools/support-crate-admission-helper/build.js',
    'tools/support-crate-admission-helper/Cargo.lock',
    'tools/support-crate-admission-helper/cargo-vendor-config.toml',
    'tools/support-crate-admission-helper/vendor',
    '.cargo/config.toml',
    '.haxerc',
    'package.json',
    'package-lock.json',
    'rust-toolchain.toml',
    'rust-toolchain-policy.json'
  ]
  const files = roots.flatMap(relative => walkFiles(path.join(repoRoot, relative)))
    .sort((left, right) => utf8Compare(path.relative(repoRoot, left), path.relative(repoRoot, right)))
  const digest = crypto.createHash('sha256')
  for (const file of files) {
    const relative = path.relative(repoRoot, file).split(path.sep).join('/')
    appendDigestFile(digest, relative, file)
  }
  appendDigestFile(digest, 'toolchain/haxe-launcher', resolvedHaxeShim)
  appendDigestFile(digest, 'toolchain/haxe-compiler', resolvedHaxeCompiler)
  const haxeStd = treeIdentity(haxeStdRoot, 'toolchain/haxe-stdlib')
  digest.update(Buffer.from(`haxe-stdlib:${haxeStd.fileCount}:${haxeStd.sha256}`, 'utf8'))
  return {
    repositoryFileCount: files.length,
    haxeStdFileCount: haxeStd.fileCount,
    sha256: digest.digest('hex')
  }
}

const cargoSourceArguments = ['--config', cargoVendorConfig, '--offline']

function lockPackages() {
  const lockText = fs.readFileSync(path.join(helperRoot, 'Cargo.lock'), 'utf8')
  const packages = new Map()
  for (const block of lockText.split('\n[[package]]\n').slice(1)) {
    const name = /^name = "([^"]+)"$/m.exec(block)?.[1]
    const version = /^version = "([^"]+)"$/m.exec(block)?.[1]
    if (!name || !version) throw new Error('Cargo.lock contains a package without name/version')
    packages.set(`${name}@${version}`, {
      source: /^source = "([^"]+)"$/m.exec(block)?.[1] || null,
      checksum: /^checksum = "([^"]+)"$/m.exec(block)?.[1] || null
    })
  }
  return packages
}

function dependencyInventory() {
  const metadata = JSON.parse(run(resolvedCargo, [
    'metadata',
    '--locked',
    ...cargoSourceArguments,
    '--format-version', '1',
    '--filter-platform', cargoTarget,
    '--manifest-path', path.join(outputRoot, 'Cargo.toml')
  ], repoRoot, cargoEnvironment))
  const locked = lockPackages()
  const idToRef = new Map(metadata.packages.map(item => [item.id, `${item.name}@${item.version}`]))
  const nodeById = new Map(metadata.resolve.nodes.map(node => [node.id, node]))
  const reachable = new Set()
  const pending = [metadata.resolve.root]
  while (pending.length > 0) {
    const id = pending.pop()
    if (reachable.has(id)) continue
    reachable.add(id)
    const node = nodeById.get(id)
    if (!node) throw new Error(`Cargo metadata root graph omits node: ${id}`)
    for (const dependency of node.dependencies) pending.push(dependency)
  }
  const packages = metadata.packages.filter(item => reachable.has(item.id)).map(item => {
    const ref = `${item.name}@${item.version}`
    const lock = locked.get(ref)
    if (!lock) throw new Error(`Cargo metadata package is absent from Cargo.lock: ${ref}`)
    const packageOwned = item.source === null
    const license = item.license || (packageOwned ? 'GPL-3.0-only' : null)
    if (!license) throw new Error(`dependency has no reviewed license expression: ${ref}`)
    return {
      ref,
      name: item.name,
      version: item.version,
      source: packageOwned ? 'package-owned' : item.source,
      checksum: lock.checksum,
      license
    }
  }).sort((left, right) => utf8Compare(left.ref, right.ref))
  const nodes = metadata.resolve.nodes.filter(node => reachable.has(node.id)).map(node => ({
    ref: idToRef.get(node.id),
    dependencies: node.dependencies.filter(id => reachable.has(id)).map(id => idToRef.get(id)).sort(utf8Compare),
    features: [...node.features].sort(utf8Compare)
  })).sort((left, right) => utf8Compare(left.ref, right.ref))
  if (nodes.some(node => !node.ref || node.dependencies.some(value => !value))) {
    throw new Error('Cargo metadata contains an unresolved dependency identity')
  }
  const irrelevant = new Set(['linux-raw-sys', 'windows-sys', 'windows-targets', 'redox_syscall'])
  if (packages.some(item => irrelevant.has(item.name))) {
    throw new Error('Darwin ARM64 dependency evidence contains another target family')
  }
  return {
    schemaVersion: 1,
    platform: packagePlatform,
    cargoTarget,
    cargoLockSha256: sha256(fs.readFileSync(path.join(helperRoot, 'Cargo.lock'))),
    packages,
    nodes
  }
}

function thirdPartyNotices(inventory) {
  const lines = [
    '# Support-crate admission helper: third-party notices',
    '',
    'This macOS helper contains the Rust dependencies listed below. The exact',
    'versions, checksums, feature graph, and package-owned components are in',
    '`dependency-inventory.json`. SPDX expressions come from Cargo metadata.',
    'This inventory does not replace professional legal advice.',
    '',
    'The helper and `hxrt` are package-owned and use GPL-3.0-only. Their full',
    'license text is the repository root `LICENSE`.',
    '',
    '## Registry dependencies',
    ''
  ]
  for (const item of inventory.packages.filter(item => item.source !== 'package-owned')) {
    lines.push(`- ${item.ref} — ${item.license} — https://crates.io/crates/${item.name}/${item.version}`)
  }
  return `${lines.join('\n')}\n`
}

function normalizedVersion(command, arguments_, admittedKeys) {
  const lines = run(command, arguments_).split('\n')
  const selected = [lines[0]]
  for (const key of admittedKeys) {
    const line = lines.find(value => value.startsWith(`${key}:`))
    if (!line) throw new Error(`${command} version output omitted ${key}`)
    selected.push(line)
  }
  return selected.join('\n')
}

function provenance(binaryBytes) {
  return {
    schemaVersion: 1,
    platform: packagePlatform,
    binarySha256: sha256(binaryBytes),
    binaryMode: '0755',
    sourceInputs: sourceInputIdentity(),
    build: {
      cargoTarget,
      sdkVersion,
      sdkSettingsSha256: sha256(fs.readFileSync(sdkSettings)),
      deploymentTarget: cargoEnvironment.MACOSX_DEPLOYMENT_TARGET,
      linkerSha256: sha256(fs.readFileSync(linker)),
      cargoConfigSha256: sha256(fs.readFileSync(path.join(repoRoot, '.cargo', 'config.toml'))),
      rustflags: '',
      cargoEncodedRustflags: '',
      cargoIncremental: false,
      cargoOffline: true,
      cargoVendored: true,
      cargoVendorConfigSha256: sha256(fs.readFileSync(cargoVendorConfig))
    },
    toolchain: {
      haxe: run(process.execPath, [resolvedHaxeShim, ...haxeScopeArguments, '--version'], repoRoot, haxeEnvironment),
      haxeLauncherSha256: sha256(fs.readFileSync(resolvedHaxeShim)),
      haxeCompilerSha256: sha256(fs.readFileSync(resolvedHaxeCompiler)),
      haxeStd: treeIdentity(haxeStdRoot, 'toolchain/haxe-stdlib'),
      node: process.version,
      nodeExecutableSha256: sha256(fs.readFileSync(process.execPath)),
      rustc: normalizedVersion(resolvedRustc, ['--version', '--verbose'], ['commit-hash', 'host', 'release', 'LLVM version']),
      rustcExecutableSha256: sha256(fs.readFileSync(resolvedRustc)),
      cargo: normalizedVersion(resolvedCargo, ['--version', '--verbose'], ['release', 'commit-hash', 'host']),
      cargoExecutableSha256: sha256(fs.readFileSync(resolvedCargo))
    }
  }
}

function verifyLocatorDigest(expected) {
  const locator = fs.readFileSync(path.join(repoRoot, 'src', 'reflaxe', 'rust', 'SupportCrateAdmissionHelperLocator.hx'), 'utf8')
  const match = /DARWIN_ARM64_SHA256:String = "([0-9a-f]{64})"/.exec(locator)
  assert.ok(match, 'helper locator does not contain one closed darwin-arm64 digest')
  assert.equal(match[1], expected, 'helper locator digest does not match the packaged binary')
}

function verifyGitMode() {
  const relative = path.relative(repoRoot, packagedBinary).split(path.sep).join('/')
  const stage = run('git', ['ls-files', '--stage', '--', relative])
  assert.match(stage, /^100755 [0-9a-f]+ 0\t/, 'packaged helper must be tracked with Git mode 100755')
}

fs.rmSync(outputRoot, { recursive: true, force: true })
run(process.execPath, [
  resolvedHaxeShim,
  ...haxeScopeArguments,
  '--cwd', helperRoot,
  'compile.hxml',
  '-D', `rust_output=${path.basename(outputRoot)}`
], repoRoot, haxeEnvironment)
fs.copyFileSync(path.join(helperRoot, 'Cargo.lock'), path.join(outputRoot, 'Cargo.lock'))
run(resolvedCargo, [
  'build',
  '--release',
  '--locked',
  ...cargoSourceArguments,
  '--target', cargoTarget,
  '--manifest-path',
  path.join(outputRoot, 'Cargo.toml')
], repoRoot, cargoEnvironment)

const builtBinary = path.join(outputRoot, 'target', cargoTarget, 'release', 'hxrs_support_crate_admission')
const builtBytes = fs.readFileSync(builtBinary)
const inventory = dependencyInventory()
const record = provenance(builtBytes)
const notices = thirdPartyNotices(inventory)

if (check) {
  const packagedBytes = fs.readFileSync(packagedBinary)
  assert.deepEqual(builtBytes, packagedBytes, 'fresh helper build differs from the packaged binary')
  assert.equal(fs.lstatSync(packagedBinary).mode & 0o777, 0o755, 'packaged helper mode must be 0755')
  assert.equal(fs.readFileSync(inventoryPath, 'utf8'), canonicalJson(inventory), 'dependency inventory is stale')
  assert.equal(fs.readFileSync(provenancePath, 'utf8'), canonicalJson(record), 'binary provenance is stale')
  assert.equal(fs.readFileSync(noticesPath, 'utf8'), notices, 'third-party notices are stale')
  verifyLocatorDigest(record.binarySha256)
  verifyGitMode()
  process.stdout.write(`verified ${path.relative(repoRoot, packagedBinary)} ${record.binarySha256}\n`)
} else {
  fs.mkdirSync(packagedDirectory, { recursive: true })
  fs.copyFileSync(builtBinary, packagedBinary)
  fs.chmodSync(packagedBinary, 0o755)
  fs.writeFileSync(inventoryPath, canonicalJson(inventory))
  fs.writeFileSync(provenancePath, canonicalJson(record))
  fs.writeFileSync(noticesPath, notices)
  process.stdout.write(`${path.relative(repoRoot, packagedBinary)} ${record.binarySha256}\n`)
}
