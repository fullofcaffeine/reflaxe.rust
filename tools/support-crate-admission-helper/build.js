#!/usr/bin/env node

const assert = require('node:assert/strict')
const crypto = require('node:crypto')
const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const helperRoot = __dirname
const repoRoot = path.resolve(helperRoot, '..', '..')
const haxe = process.env.HAXE_BIN || path.join(
  repoRoot,
  'node_modules',
  '.bin',
  process.platform === 'win32' ? 'haxe.cmd' : 'haxe'
)
const cargo = process.env.CARGO_BIN || 'cargo'
const rustc = process.env.RUSTC_BIN || 'rustc'
const host = `${process.platform}-${process.arch}`
const packagePlatform = new Map([
  ['darwin-arm64', 'darwin-arm64'],
  ['linux-x64', 'linux-x86_64']
]).get(host)
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

function run(command, args, cwd = repoRoot) {
  const result = spawnSync(command, args, { cwd, encoding: 'utf8', env: process.env })
  assert.ifError(result.error)
  if (result.status !== 0) {
    throw new Error(`${command} failed:\n${result.stdout || ''}${result.stderr || ''}`)
  }
  return result.stdout.trim()
}

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
    'package.json',
    'package-lock.json',
    'rust-toolchain.toml',
    'rust-toolchain-policy.json'
  ]
  const files = roots.flatMap(relative => walkFiles(path.join(repoRoot, relative)))
    .sort((left, right) => path.relative(repoRoot, left).localeCompare(path.relative(repoRoot, right), 'en'))
  const digest = crypto.createHash('sha256')
  for (const file of files) {
    const relative = path.relative(repoRoot, file).split(path.sep).join('/')
    const bytes = fs.readFileSync(file)
    digest.update(Buffer.from(`${Buffer.byteLength(relative)}:${relative}:${bytes.length}:`, 'utf8'))
    digest.update(bytes)
  }
  return { fileCount: files.length, sha256: digest.digest('hex') }
}

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
  const metadata = JSON.parse(run(cargo, [
    'metadata',
    '--locked',
    '--format-version', '1',
    '--manifest-path', path.join(outputRoot, 'Cargo.toml')
  ]))
  const locked = lockPackages()
  const idToRef = new Map(metadata.packages.map(item => [item.id, `${item.name}@${item.version}`]))
  const packages = metadata.packages.map(item => {
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
  }).sort((left, right) => left.ref.localeCompare(right.ref, 'en'))
  const nodes = metadata.resolve.nodes.map(node => ({
    ref: idToRef.get(node.id),
    dependencies: node.dependencies.map(id => idToRef.get(id)).sort((left, right) => left.localeCompare(right, 'en')),
    features: [...node.features].sort((left, right) => left.localeCompare(right, 'en'))
  })).sort((left, right) => left.ref.localeCompare(right.ref, 'en'))
  if (nodes.some(node => !node.ref || node.dependencies.some(value => !value))) {
    throw new Error('Cargo metadata contains an unresolved dependency identity')
  }
  return {
    schemaVersion: 1,
    platform: packagePlatform,
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
    toolchain: {
      haxe: run(haxe, ['--version']),
      rustc: normalizedVersion(rustc, ['--version', '--verbose'], ['commit-hash', 'host', 'release', 'LLVM version']),
      cargo: normalizedVersion(cargo, ['--version', '--verbose'], ['release', 'commit-hash', 'host'])
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
run(haxe, ['compile.hxml', '-D', `rust_output=${path.basename(outputRoot)}`], helperRoot)
fs.copyFileSync(path.join(helperRoot, 'Cargo.lock'), path.join(outputRoot, 'Cargo.lock'))
run(cargo, [
  'build',
  '--release',
  '--locked',
  '--manifest-path',
  path.join(outputRoot, 'Cargo.toml')
])

const builtBinary = path.join(outputRoot, 'target', 'release', 'hxrs_support_crate_admission')
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
