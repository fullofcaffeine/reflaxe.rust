#!/usr/bin/env node
/**
 * Why:
 * The repository must reproduce the dependency graph that reviewers accepted. It must also notice
 * new crates.io releases without allowing mutable registry state to veto an unrelated source change.
 *
 * What:
 * `verify-reviewed` checks the tracked locks with frozen Cargo commands. `observe-live` creates a
 * digest-bound candidate without changing tracked files. `admit` verifies that exact candidate and
 * installs it without asking Cargo to resolve again.
 *
 * How:
 * All three modes use a paired Cargo/rustc sysroot and a controlled environment. Reviewed and
 * admitted graphs retain normalized metadata because a Cargo lock alone does not show enabled
 * features, dependency kinds, target conditions, declared Rust versions, or resolved topology.
 */

const cp = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const policyPath = path.join(repoRoot, 'rust-toolchain-policy.json')
const cargoBin = process.env.CARGO_BIN || 'cargo'
const rustcBin = process.env.RUSTC_BIN || 'rustc'
const commandTimeoutMs = Number.parseInt(process.env.FRESH_CARGO_COMMAND_TIMEOUT_MS || '900000', 10)
const normalizationSchemaVersion = 2
const baselineSchemaVersion = 2
const observationSchemaVersion = 1
const { validateManifest } = require('./rust-toolchain-policy.js')

function diagnostic(id, message) {
  return new Error(`${id}: ${message}`)
}

function fail(id, message) {
  throw diagnostic(id, message)
}

function parseJsonBytes(bytes, label, id) {
  try {
    const value = JSON.parse(bytes.toString('utf8'))
    if (!bytes.equals(jsonBytes(value))) fail(id, `${label} must use canonical JSON bytes`)
    return value
  } catch (error) {
    if (error.message != null && error.message.startsWith(`${id}:`)) throw error
    fail(id, `cannot read ${label}: ${error.message}`)
  }
}

function readJson(filePath, label, id = 'FCR020_BASELINE_INTEGRITY') {
  try {
    return parseJsonBytes(fs.readFileSync(filePath), label, id)
  } catch (error) {
    if (error.message != null && error.message.startsWith(`${id}:`)) throw error
    fail(id, `cannot read ${label}: ${error.message}`)
  }
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function jsonBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`)
}

function compareText(left, right) {
  return Buffer.compare(Buffer.from(left), Buffer.from(right))
}

function argumentValue(args, name, fallback = null) {
  const indexes = args.flatMap((value, index) => value === name ? [index] : [])
  if (indexes.length === 0) return fallback
  if (indexes.length > 1) fail('FCR900_USAGE', `${name} must appear at most once`)
  const index = indexes[0]
  if (index + 1 >= args.length) fail('FCR900_USAGE', `${name} requires a value`)
  return args[index + 1]
}

function parseRustVersion(value) {
  const match = /^(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))?(?:\.(0|[1-9][0-9]*))?$/.exec(value || '')
  if (match == null) return null
  return [match[1], match[2] || '0', match[3] || '0'].map((part) => BigInt(part))
}

function compareRustVersions(left, right) {
  const leftParts = parseRustVersion(left)
  const rightParts = parseRustVersion(right)
  if (leftParts == null || rightParts == null) fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', `cannot compare Rust versions ${left} and ${right}`)
  for (let index = 0; index < leftParts.length; index += 1) {
    if (leftParts[index] < rightParts[index]) return -1
    if (leftParts[index] > rightParts[index]) return 1
  }
  return 0
}

function canonicalVersion(value) {
  const parts = parseRustVersion(value)
  if (parts == null) fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', `invalid Rust tool version: ${value}`)
  return parts.map((part) => part.toString()).join('.')
}

function nextRustMinor(value) {
  const parts = parseRustVersion(value)
  if (parts == null) fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', `invalid Rust version: ${value}`)
  return `${parts[0]}.${parts[1] + 1n}.0`
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function sanitizeOutput(value, replacements) {
  let out = value || ''
  const ordered = replacements.filter(([from]) => typeof from === 'string' && from.length > 0)
    .sort((left, right) => right[0].length - left[0].length)
  for (const [from, to] of ordered) out = out.replace(new RegExp(escapeRegExp(from), 'g'), to)
  return out
}

function runCommand(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {
    cwd: options.cwd || repoRoot,
    env: options.env || process.env,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    timeout: commandTimeoutMs
  })
  if (result.error != null && result.error.code === 'ETIMEDOUT') fail(options.id || 'FCR022_REVIEWED_GRAPH_INCOMPATIBLE', `${options.label || command} exceeded ${commandTimeoutMs}ms`)
  if (result.error != null) fail(options.id || 'FCR022_REVIEWED_GRAPH_INCOMPATIBLE', `${options.label || command} could not start: ${sanitizeOutput(result.error.message, options.replacements || [])}`)
  if (!options.allowFailure && result.status !== 0) {
    const output = sanitizeOutput(`${result.stdout || ''}\n${result.stderr || ''}`, options.replacements || [])
    fail(options.id || 'FCR022_REVIEWED_GRAPH_INCOMPATIBLE', `${options.label || command} failed with status ${result.status}\n${output.trim()}`)
  }
  return result
}

function loadPolicy() {
  const policy = readJson(policyPath, 'Rust toolchain policy')
  const errors = validateManifest(policy)
  if (errors.length > 0) fail('FCR020_BASELINE_INTEGRITY', `invalid Rust toolchain policy:\n- ${errors.join('\n- ')}`)
  return policy
}

function exactManifestField(source, field) {
  const escaped = field.replace('-', '\\-')
  const match = source.match(new RegExp(`^${escaped} = "([^"]+)"$`, 'm'))
  return match == null ? null : match[1]
}

function verifyFixtureManifests(policy, snapshot = null) {
  for (const entry of policy.dependencyResolution.cases) {
    const source = fs.readFileSync(path.join(snapshotFixtureRoot(snapshot, entry), 'Cargo.toml'), 'utf8')
    if (exactManifestField(source, 'rust-version') !== policy.minimumSupportedRust) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `${entry.id} fixture rust-version does not match ${policy.minimumSupportedRust}`)
    if (exactManifestField(source, 'resolver') !== policy.dependencyResolution.resolverVersion) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `${entry.id} fixture resolver does not match ${policy.dependencyResolution.resolverVersion}`)
  }
}

function toolVersion(command, label) {
  const result = runCommand(command, ['--version'], { label, id: 'FCR010_TOOLCHAIN_PAIR_MISMATCH' })
  const match = new RegExp(`^${label} ([^ ]+)`).exec(result.stdout.trim())
  if (match == null) fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', `cannot parse ${label} version from: ${result.stdout.trim()}`)
  return match[1]
}

function selectToolchainCommands(options = {}) {
  const rustcCommand = options.rustcCommand || rustcBin
  const cargoCommand = options.cargoCommand || cargoBin
  const rustcExplicit = options.rustcExplicit == null ? process.env.RUSTC_BIN != null : options.rustcExplicit
  const cargoExplicit = options.cargoExplicit == null ? process.env.CARGO_BIN != null : options.cargoExplicit
  if (rustcExplicit && cargoExplicit) return { rustc: rustcCommand, cargo: cargoCommand }

  const readRustcSysroot = options.readRustcSysroot || (() => runCommand(rustcCommand, ['--print', 'sysroot'], {
    label: 'selected rustc sysroot', id: 'FCR010_TOOLCHAIN_PAIR_MISMATCH'
  }).stdout.trim())
  const pathExists = options.pathExists || fs.existsSync
  const executableSuffix = (options.platform || process.platform) === 'win32' ? '.exe' : ''
  const sysroot = readRustcSysroot()
  if (typeof sysroot !== 'string' || sysroot.trim().length === 0) fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', 'selected rustc returned an empty sysroot')
  const selectedRustc = path.join(sysroot, 'bin', `rustc${executableSuffix}`)
  const selectedCargo = path.join(sysroot, 'bin', `cargo${executableSuffix}`)
  if (!rustcExplicit && !pathExists(selectedRustc)) fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', `selected Rust sysroot does not contain rustc at ${selectedRustc}`)
  if (!cargoExplicit && !pathExists(selectedCargo)) fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', `selected Rust sysroot does not contain cargo at ${selectedCargo}`)
  return { rustc: rustcExplicit ? rustcCommand : selectedRustc, cargo: cargoExplicit ? cargoCommand : selectedCargo }
}

function loadSelectedToolchain(options = {}) {
  const commands = selectToolchainCommands(options)
  const sysroot = runCommand(commands.rustc, ['--print', 'sysroot'], { label: 'selected rustc sysroot', id: 'FCR010_TOOLCHAIN_PAIR_MISMATCH' }).stdout.trim()
  const suffix = process.platform === 'win32' ? '.exe' : ''
  const expectedCargo = fs.realpathSync(path.join(sysroot, 'bin', `cargo${suffix}`))
  const actualCargo = fs.realpathSync(commands.cargo)
  const expectedRustc = fs.realpathSync(path.join(sysroot, 'bin', `rustc${suffix}`))
  const actualRustc = fs.realpathSync(commands.rustc)
  if (actualCargo !== expectedCargo || actualRustc !== expectedRustc) {
    fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', 'Cargo and rustc must be sibling binaries from the selected Rust sysroot')
  }
  return {
    rustc: actualRustc,
    cargo: actualCargo,
    rustcVersion: canonicalVersion(toolVersion(commands.rustc, 'rustc')),
    cargoVersion: canonicalVersion(toolVersion(commands.cargo, 'cargo')),
    sysroot
  }
}

const prohibitedEnvironmentExact = new Set([
  'CARGO_NET_OFFLINE', 'CARGO_BUILD_TARGET', 'CARGO_ENCODED_RUSTFLAGS', 'CARGO_INCREMENTAL',
  'CARGO_ENCODED_RUSTDOCFLAGS', 'RUSTC_BOOTSTRAP', 'RUSTFLAGS', 'RUSTC_WRAPPER',
  'RUSTC_WORKSPACE_WRAPPER', 'RUSTDOC', 'RUSTDOCFLAGS'
])

const cargoTransportEnvironment = new Set([
  'CARGO_HTTP_CAINFO', 'CARGO_HTTP_CHECK_REVOKE', 'CARGO_HTTP_DEBUG',
  'CARGO_HTTP_LOW_SPEED_LIMIT', 'CARGO_HTTP_MULTIPLEXING', 'CARGO_HTTP_PROXY',
  'CARGO_HTTP_SSL_VERSION', 'CARGO_HTTP_TIMEOUT', 'CARGO_NET_GIT_FETCH_WITH_CLI',
  'CARGO_NET_RETRY', 'CARGO_NET_SSH_KNOWN_HOSTS'
])

const operatingEnvironment = new Set([
  'COMSPEC', 'HOMEDRIVE', 'HOMEPATH', 'LANG', 'LC_ALL', 'LC_CTYPE', 'LOCALAPPDATA',
  'LOGNAME', 'NUMBER_OF_PROCESSORS', 'OS', 'PATHEXT', 'PROCESSOR_ARCHITECTURE',
  'PATH', 'SYSTEMDRIVE', 'SYSTEMROOT', 'TERM', 'TZ', 'USER', 'USERNAME',
  'WINDIR'
])

function environmentAffectsResolutionOrBuild(name) {
  return prohibitedEnvironmentExact.has(name)
    || /^CARGO_(BUILD|PROFILE|REGISTRIES|REGISTRY|SOURCE|TARGET)_/.test(name)
}

function assertControlledEnvironment(environment = process.env) {
  const bad = Object.keys(environment).filter(environmentAffectsResolutionOrBuild)
  if (bad.length > 0) fail('FCR011_UNCONTROLLED_ENVIRONMENT', `unset resolution-affecting environment variable(s): ${bad.sort(compareText).join(', ')}`)
}

function controlledCargoEnvironment(environment = process.env) {
  assertControlledEnvironment(environment)
  const controlled = {}
  for (const [name, value] of Object.entries(environment)) {
    if (operatingEnvironment.has(name) || cargoTransportEnvironment.has(name)
        || name === 'HTTP_PROXY' || name === 'HTTPS_PROXY' || name === 'NO_PROXY'
        || name === 'http_proxy' || name === 'https_proxy' || name === 'no_proxy') {
      controlled[name] = value
    }
  }
  return controlled
}

function assertNoAncestorCargoConfiguration(directory, allowedRoot) {
  let current = path.resolve(directory)
  const allowed = path.resolve(allowedRoot)
  while (true) {
    const cargoDirectory = path.join(current, '.cargo')
    for (const name of ['config', 'config.toml']) {
      const config = path.join(cargoDirectory, name)
      if (fs.existsSync(config) && !path.resolve(config).startsWith(`${allowed}${path.sep}`)) {
        fail('FCR011_UNCONTROLLED_ENVIRONMENT', `Cargo configuration outside the retained fixture snapshot is not allowed: ${name}`)
      }
    }
    const parent = path.dirname(current)
    if (parent === current) break
    current = parent
  }
}

function stablePackageKey(pkg) {
  return `${pkg.name}@${pkg.version}${pkg.source == null ? ':path' : `:${pkg.source}`}`
}

function normalizeDependency(dependency) {
  return {
    name: dependency.name,
    rename: dependency.rename || null,
    requirement: dependency.req,
    source: dependency.source || 'path',
    kind: dependency.kind || 'normal',
    optional: dependency.optional,
    usesDefaultFeatures: dependency.uses_default_features,
    features: [...dependency.features].sort(compareText),
    target: dependency.target || null
  }
}

function normalizeResolvedDependency(dependency, packageKeyById) {
  const packageId = packageKeyById.get(dependency.pkg)
  if (packageId == null) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `Cargo metadata resolve edge points to unknown package ${dependency.pkg}`)
  return {
    name: dependency.name,
    package: packageId,
    kinds: (dependency.dep_kinds || []).map((kind) => ({ kind: kind.kind || 'normal', target: kind.target || null }))
      .sort((left, right) => compareText(JSON.stringify(left), JSON.stringify(right)))
  }
}

function normalizeMetadata(raw, entry, policy, options = {}) {
  const packageKeyById = new Map(raw.packages.map((pkg) => [pkg.id, stablePackageKey(pkg)]))
  const featuresById = new Map((raw.resolve && raw.resolve.nodes || []).map((node) => [node.id, [...node.features].sort(compareText)]))
  const rootPackage = raw.resolve && raw.resolve.root != null ? packageKeyById.get(raw.resolve.root) : null
  if (rootPackage == null) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `${entry.id} Cargo metadata has no stable root package`)
  const packages = raw.packages.map((pkg) => ({
    id: stablePackageKey(pkg), name: pkg.name, version: pkg.version, source: pkg.source || 'path',
    rustVersion: pkg.rust_version == null ? null : canonicalVersion(pkg.rust_version),
    enabledFeatures: featuresById.get(pkg.id) || [],
    dependencies: pkg.dependencies.map(normalizeDependency).sort((left, right) => compareText(JSON.stringify(left), JSON.stringify(right)))
  })).sort((left, right) => compareText(left.id, right.id))
  const incompatible = packages.filter((pkg) => pkg.rustVersion != null && compareRustVersions(pkg.rustVersion, policy.minimumSupportedRust) > 0)
  if (!options.allowIncompatible && incompatible.length > 0) fail('FCR102_OBSERVATION_INCOMPATIBLE', `${entry.id} resolved dependencies declaring Rust newer than ${policy.minimumSupportedRust}: ${incompatible.map((pkg) => `${pkg.name}@${pkg.version}=${pkg.rustVersion}`).join(', ')}`)
  const resolveNodes = (raw.resolve.nodes || []).map((node) => {
    const id = packageKeyById.get(node.id)
    if (id == null) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `${entry.id} Cargo metadata resolve graph contains an unknown package`)
    const dependencies = Array.isArray(node.deps)
      ? node.deps.map((dependency) => normalizeResolvedDependency(dependency, packageKeyById))
      : (node.dependencies || []).map((dependencyId) => ({ name: null, package: packageKeyById.get(dependencyId), kinds: [] }))
    dependencies.sort((left, right) => compareText(JSON.stringify(left), JSON.stringify(right)))
    return { id, enabledFeatures: [...node.features].sort(compareText), dependencies }
  }).sort((left, right) => compareText(left.id, right.id))
  const normalizeIds = (values, owner) => (values || []).map((id) => {
    const stable = packageKeyById.get(id)
    if (stable == null) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `${entry.id} Cargo metadata ${owner} contains an unknown package`)
    return stable
  }).sort(compareText)
  return {
    schemaVersion: normalizationSchemaVersion,
    caseId: entry.id,
    contract: entry.contract,
    fixture: entry.fixture,
    minimumSupportedRust: policy.minimumSupportedRust,
    resolverVersion: policy.dependencyResolution.resolverVersion,
    incompatibleRustVersions: options.incompatibleRustVersions || policy.dependencyResolution.incompatibleRustVersions,
    rootPackage,
    workspaceMembers: normalizeIds(raw.workspace_members, 'workspace_members'),
    workspaceDefaultMembers: normalizeIds(raw.workspace_default_members, 'workspace_default_members'),
    resolvedGraph: { root: rootPackage, nodes: resolveNodes },
    packages
  }
}

function cargoEnvironment(cargoHome, targetDir, toolchain) {
  const environment = controlledCargoEnvironment()
  return {
    ...environment,
    HOME: path.dirname(cargoHome),
    USERPROFILE: path.dirname(cargoHome),
    TMPDIR: path.dirname(cargoHome),
    TMP: path.dirname(cargoHome),
    TEMP: path.dirname(cargoHome),
    CARGO_HOME: cargoHome,
    CARGO_TARGET_DIR: targetDir,
    CARGO_TERM_COLOR: 'never',
    CARGO_NET_RETRY: process.env.CARGO_NET_RETRY || '10',
    CARGO_HTTP_MULTIPLEXING: process.env.CARGO_HTTP_MULTIPLEXING || 'false',
    RUSTC: toolchain.rustc,
    RUSTDOC: path.join(toolchain.sysroot, 'bin', `rustdoc${process.platform === 'win32' ? '.exe' : ''}`)
  }
}

function resolutionInputFiles(fixtureRoot) {
  const out = []
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => compareText(a.name, b.name))) {
      if (entry.name === 'target' || entry.name === 'Cargo.lock') continue
      const full = path.join(directory, entry.name)
      if (entry.isSymbolicLink()) fail('FCR011_UNCONTROLLED_ENVIRONMENT', 'Cargo input trees must not contain symlinks')
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile() && (entry.name === 'Cargo.toml' || /(^|[/\\])\.cargo[/\\]config(?:\.toml)?$/.test(full))) out.push(full)
      else if (!entry.isFile()) fail('FCR011_UNCONTROLLED_ENVIRONMENT', 'Cargo input trees must contain only directories and regular files')
    }
  }
  visit(fixtureRoot)
  return out.sort(compareText)
}

function resolutionInputDigest(entry) {
  const root = path.join(repoRoot, entry.fixture)
  const hash = crypto.createHash('sha256')
  for (const file of resolutionInputFiles(root)) {
    const relative = path.relative(root, file).split(path.sep).join('/')
    const bytes = fs.readFileSync(file)
    hash.update(`${relative}\0${bytes.length}\0`)
    hash.update(bytes)
  }
  return hash.digest('hex')
}

function fixtureTreeDigest(root) {
  const hash = crypto.createHash('sha256')
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => compareText(left.name, right.name))) {
      if (entry.name === 'target' || entry.name === 'Cargo.lock') continue
      const full = path.join(directory, entry.name)
      const relative = path.relative(root, full).split(path.sep).join('/')
      if (entry.isSymbolicLink()) fail('FCR200_ADMISSION_STALE_BASE', `fixture input must not contain symlink ${relative}`)
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile()) {
        const bytes = fs.readFileSync(full)
        hash.update(`${relative}\0${bytes.length}\0`)
        hash.update(bytes)
      } else fail('FCR200_ADMISSION_STALE_BASE', `fixture input must contain only directories and regular files: ${relative}`)
    }
  }
  visit(root)
  return hash.digest('hex')
}

function captureAuthoritySnapshot(policy) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-rust-cargo-authority-'))
  const policyBytes = fs.readFileSync(policyPath)
  if (!policyBytes.equals(jsonBytes(policy))) {
    fs.rmSync(root, { recursive: true, force: true })
    fail('FCR200_ADMISSION_STALE_BASE', 'Rust toolchain policy changed while it was being captured')
  }
  const inputDigests = new Map()
  const fixtureDigests = new Map()
  try {
    for (const entry of policy.dependencyResolution.cases) {
      const source = path.join(repoRoot, entry.fixture)
      const target = path.join(root, 'fixtures', entry.id)
      fs.cpSync(source, target, { recursive: true })
      const sourceDigest = fixtureTreeDigest(source)
      const targetDigest = fixtureTreeDigest(target)
      if (sourceDigest !== targetDigest) fail('FCR200_ADMISSION_STALE_BASE', `${entry.id} changed while its fixture was captured`)
      fixtureDigests.set(entry.id, sourceDigest)
      const snapshotEntry = { ...entry, fixture: path.relative(repoRoot, target) }
      inputDigests.set(entry.id, resolutionInputDigest(snapshotEntry))
    }
  } catch (error) {
    fs.rmSync(root, { recursive: true, force: true })
    throw error
  }
  return { root, policyBytes, inputDigests, fixtureDigests }
}

function snapshotFixtureRoot(snapshot, entry) {
  return snapshot == null
    ? path.join(repoRoot, entry.fixture)
    : path.join(snapshot.root, 'fixtures', entry.id)
}

function assertAuthoritySnapshotCurrent(policy, snapshot) {
  if (snapshot == null) return
  if (!fs.readFileSync(policyPath).equals(snapshot.policyBytes)) {
    fail('FCR200_ADMISSION_STALE_BASE', 'Rust toolchain policy changed during the operation')
  }
  for (const entry of policy.dependencyResolution.cases) {
    if (fixtureTreeDigest(path.join(repoRoot, entry.fixture)) !== snapshot.fixtureDigests.get(entry.id)) {
      fail('FCR200_ADMISSION_STALE_BASE', `${entry.id} fixture changed during the operation`)
    }
    if (resolutionInputDigest(entry) !== snapshot.inputDigests.get(entry.id)) {
      fail('FCR200_ADMISSION_STALE_BASE', `${entry.id} resolution input changed during the operation`)
    }
  }
}

function baselineDirectory(policy) {
  return path.resolve(repoRoot, policy.dependencyResolution.evidenceBaseline)
}

function publicationPaths(root) {
  const scope = sha256(path.relative(repoRoot, root)).slice(0, 16)
  const parent = path.dirname(root)
  return {
    lock: path.join(parent, `.fresh-cargo-${scope}.lock`),
    journal: path.join(parent, `.fresh-cargo-${scope}.journal.json`),
    staged: path.join(parent, `.fresh-cargo-${scope}.staged`),
    previous: path.join(parent, `.fresh-cargo-${scope}.previous`)
  }
}

function processIsRunning(pid) {
  if (!Number.isInteger(pid) || pid < 1) return false
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    return error.code !== 'ESRCH'
  }
}

function acquirePublicationLock(root) {
  const paths = publicationPaths(root)
  const deadline = Date.now() + 10000
  while (true) {
    try {
      const fd = fs.openSync(paths.lock, 'wx', 0o600)
      fs.writeFileSync(fd, jsonBytes({ schemaVersion: 1, pid: process.pid }))
      return { fd, path: paths.lock }
    } catch (error) {
      if (error.code !== 'EEXIST') throw error
      let owner = null
      try {
        owner = readJson(paths.lock, 'Cargo baseline publication lock')
      } catch (_error) {
        if (Date.now() >= deadline) fail('FCR204_PUBLICATION_BUSY', 'the Cargo baseline publication lock is unreadable; inspect it before removal')
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50)
        continue
      }
      if (!processIsRunning(owner.pid)) {
        fs.rmSync(paths.lock, { force: true })
        continue
      }
      if (Date.now() >= deadline) fail('FCR204_PUBLICATION_BUSY', 'another Cargo baseline operation holds the publication lock')
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 50)
    }
  }
}

function releasePublicationLock(lock) {
  fs.closeSync(lock.fd)
  fs.rmSync(lock.path, { force: true })
}

function recoverBaselinePublication(root) {
  const paths = publicationPaths(root)
  if (!fs.existsSync(paths.journal)) return
  const journal = readJson(paths.journal, 'Cargo baseline publication journal')
  assertExactObject(journal, ['schemaVersion'], 'Cargo baseline publication journal', 'FCR205_PUBLICATION_RECOVERY')
  if (journal.schemaVersion !== 1) {
    fail('FCR205_PUBLICATION_RECOVERY', 'Cargo baseline publication journal is invalid')
  }
  const rootExists = fs.existsSync(root)
  const previousExists = fs.existsSync(paths.previous)
  const stagedExists = fs.existsSync(paths.staged)
  if (!rootExists && previousExists) fs.renameSync(paths.previous, root)
  else if (rootExists && previousExists) fs.rmSync(paths.previous, { recursive: true, force: true })
  else if (!rootExists) fail('FCR205_PUBLICATION_RECOVERY', 'Cargo baseline and recovery copy are both missing')
  if (stagedExists) fs.rmSync(paths.staged, { recursive: true, force: true })
  fs.rmSync(paths.journal, { force: true })
}

function policyForReviewedBaseline(currentPolicy, manifest) {
  assertExactObject(manifest, [
    'schemaVersion', 'authority', 'policySchemaVersion', 'policySha256',
    'normalizationSchemaVersion', 'minimumSupportedRust', 'admittedRustcVersion',
    'admittedCargoVersion', 'resolverVersion', 'incompatibleRustVersions',
    'applicationLockfile', 'requiredGate', 'observationMode', 'admissionToolchain',
    'lockfileFormat', 'cases'
  ], 'reviewed graph manifest')
  assertArray(manifest.cases, 'reviewed graph manifest.cases')
  const caseIds = new Set()
  const cases = manifest.cases.map((entry, index) => {
    assertExactObject(entry, [
      'id', 'contract', 'fixture', 'resolutionInputSha256', 'lockSha256', 'metadataSha256'
    ], `reviewed graph manifest.cases[${index}]`)
    if (caseIds.has(entry.id)) fail('FCR020_BASELINE_INTEGRITY', `reviewed graph manifest repeats case ${entry.id}`)
    caseIds.add(entry.id)
    assertDigest(entry.resolutionInputSha256, `reviewed graph manifest.cases[${index}].resolutionInputSha256`)
    assertDigest(entry.lockSha256, `reviewed graph manifest.cases[${index}].lockSha256`)
    assertDigest(entry.metadataSha256, `reviewed graph manifest.cases[${index}].metadataSha256`)
    return {
      id: entry.id,
      contract: entry.contract,
      fixture: entry.fixture
    }
  })
  return {
    schemaVersion: manifest.policySchemaVersion,
    minimumSupportedRust: manifest.minimumSupportedRust,
    dependencyResolution: {
      resolverVersion: manifest.resolverVersion,
      incompatibleRustVersions: manifest.incompatibleRustVersions,
      applicationLockfile: manifest.applicationLockfile,
      evidenceBaseline: currentPolicy.dependencyResolution.evidenceBaseline,
      requiredGate: manifest.requiredGate,
      observationMode: manifest.observationMode,
      admissionToolchain: manifest.admissionToolchain,
      cases
    }
  }
}

function artifactsFromDirectory(policy, root, id = 'FCR020_BASELINE_INTEGRITY') {
  const artifacts = new Map()
  for (const entry of policy.dependencyResolution.cases) {
    const caseRoot = path.join(root, entry.id)
    const lockPath = path.join(caseRoot, 'Cargo.lock')
    const metadataPath = path.join(caseRoot, 'metadata.json')
    if (!fs.existsSync(lockPath) || !fs.existsSync(metadataPath)) fail(id, `missing ${entry.id} lock or metadata evidence`)
    artifacts.set(entry.id, { lock: fs.readFileSync(lockPath), metadata: fs.readFileSync(metadataPath) })
  }
  return artifacts
}

function assertBaselineFileInventory(policy, root) {
  const expected = new Set(['README.md', 'manifest.json'])
  for (const entry of policy.dependencyResolution.cases) {
    expected.add(`${entry.id}/Cargo.lock`)
    expected.add(`${entry.id}/metadata.json`)
  }
  const actual = new Set()
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((left, right) => compareText(left.name, right.name))) {
      const full = path.join(directory, entry.name)
      const relative = path.relative(root, full).split(path.sep).join('/')
      if (entry.isSymbolicLink()) fail('FCR020_BASELINE_INTEGRITY', `reviewed graph must not contain symlink ${relative}`)
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile()) actual.add(relative)
      else fail('FCR020_BASELINE_INTEGRITY', `reviewed graph must contain only directories and regular files: ${relative}`)
    }
  }
  const stat = fs.lstatSync(root)
  if (stat.isSymbolicLink() || !stat.isDirectory()) fail('FCR020_BASELINE_INTEGRITY', 'reviewed graph root must be a real directory')
  visit(root)
  const missing = [...expected].filter((entry) => !actual.has(entry))
  const extra = [...actual].filter((entry) => !expected.has(entry))
  if (missing.length > 0 || extra.length > 0) {
    fail('FCR020_BASELINE_INTEGRITY', `reviewed graph file inventory differs (missing=${missing.sort(compareText).join(',') || 'none'}; extra=${extra.sort(compareText).join(',') || 'none'})`)
  }
}

function assertBaselineRoot(root, allowMissing = false) {
  let stat
  try {
    stat = fs.lstatSync(root)
  } catch (error) {
    if (allowMissing && error.code === 'ENOENT') return
    fail('FCR020_BASELINE_INTEGRITY', `cannot inspect reviewed graph root: ${error.message}`)
  }
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    fail('FCR020_BASELINE_INTEGRITY', 'reviewed graph root must be a real directory')
  }
}

function assertBaselineManifestFile(manifestPath) {
  let stat
  try {
    stat = fs.lstatSync(manifestPath)
  } catch (error) {
    fail('FCR020_BASELINE_INTEGRITY', `cannot inspect reviewed graph manifest: ${error.message}`)
  }
  if (stat.isSymbolicLink() || !stat.isFile()) {
    fail('FCR020_BASELINE_INTEGRITY', 'reviewed graph manifest must be a regular file')
  }
}

function lockfileFormat(bytes) {
  const match = /^version = ([0-9]+)$/m.exec(bytes.toString('utf8'))
  if (match == null) fail('FCR020_BASELINE_INTEGRITY', 'Cargo.lock has no supported lockfile version')
  return Number.parseInt(match[1], 10)
}

function policyDigest() {
  return sha256(fs.readFileSync(policyPath))
}

function buildBaselineManifest(policy, artifacts, toolchainIdentity, options = {}) {
  const formats = new Set([...artifacts.values()].map((artifact) => lockfileFormat(artifact.lock)))
  if (formats.size !== 1) fail('FCR020_BASELINE_INTEGRITY', 'reviewed Cargo locks use different format versions')
  return {
    schemaVersion: baselineSchemaVersion,
    authority: 'reviewed-lock',
    policySchemaVersion: policy.schemaVersion,
    policySha256: options.policySha256 || policyDigest(),
    normalizationSchemaVersion: options.normalizationSchemaVersion || normalizationSchemaVersion,
    minimumSupportedRust: policy.minimumSupportedRust,
    admittedRustcVersion: toolchainIdentity.rustcVersion,
    admittedCargoVersion: toolchainIdentity.cargoVersion,
    resolverVersion: policy.dependencyResolution.resolverVersion,
    incompatibleRustVersions: policy.dependencyResolution.incompatibleRustVersions,
    applicationLockfile: policy.dependencyResolution.applicationLockfile,
    requiredGate: policy.dependencyResolution.requiredGate,
    observationMode: policy.dependencyResolution.observationMode,
    admissionToolchain: policy.dependencyResolution.admissionToolchain,
    lockfileFormat: [...formats][0],
    cases: policy.dependencyResolution.cases.map((entry) => ({
      id: entry.id,
      contract: entry.contract,
      fixture: entry.fixture,
      resolutionInputSha256: options.resolutionInputDigests == null
        ? resolutionInputDigest(entry)
        : options.resolutionInputDigests.get(entry.id),
      lockSha256: sha256(artifacts.get(entry.id).lock),
      metadataSha256: sha256(artifacts.get(entry.id).metadata)
    }))
  }
}

function checkBaseline(policy, options = {}) {
  const root = baselineDirectory(policy)
  const lock = acquirePublicationLock(root)
  try {
    assertBaselineRoot(root, true)
    recoverBaselinePublication(root)
    assertBaselineRoot(root)
    const manifestPath = path.join(root, 'manifest.json')
    assertBaselineManifestFile(manifestPath)
    const manifest = readJson(manifestPath, 'reviewed graph manifest')
    if (manifest.schemaVersion !== baselineSchemaVersion || manifest.authority !== 'reviewed-lock') fail('FCR020_BASELINE_INTEGRITY', 'reviewed graph manifest schema or authority is invalid')
    const baselinePolicy = policyForReviewedBaseline(policy, manifest)
    assertBaselineFileInventory(baselinePolicy, root)
    const artifacts = artifactsFromDirectory(baselinePolicy, root)
    for (const entry of baselinePolicy.dependencyResolution.cases) {
      const metadata = parseJsonBytes(artifacts.get(entry.id).metadata, `${entry.id} reviewed metadata`, 'FCR020_BASELINE_INTEGRITY')
      assertNormalizedMetadataShape(metadata, `${entry.id} reviewed metadata`)
      if (metadata.schemaVersion !== manifest.normalizationSchemaVersion) {
        fail('FCR020_BASELINE_INTEGRITY', `${entry.id} reviewed metadata uses the wrong normalization schema`)
      }
    }
    const baselineInputs = new Map(manifest.cases.map((entry) => [entry.id, entry.resolutionInputSha256]))
    const expected = buildBaselineManifest(baselinePolicy, artifacts, {
      rustcVersion: manifest.admittedRustcVersion,
      cargoVersion: manifest.admittedCargoVersion
    }, {
      policySha256: manifest.policySha256,
      resolutionInputDigests: baselineInputs,
      normalizationSchemaVersion: manifest.normalizationSchemaVersion
    })
    if (!jsonBytes(expected).equals(fs.readFileSync(manifestPath))) fail('FCR020_BASELINE_INTEGRITY', 'reviewed graph manifest, inputs, or artifact digests are stale')
    if (!options.allowCurrentAuthorityChange) {
      if (manifest.policySha256 !== policyDigest()) fail('FCR020_BASELINE_INTEGRITY', 'reviewed graph policy digest is stale')
      if (manifest.cases.length !== policy.dependencyResolution.cases.length) fail('FCR020_BASELINE_INTEGRITY', 'reviewed graph case inventory is stale')
      for (const entry of policy.dependencyResolution.cases) {
        const reviewed = manifest.cases.find((candidate) => candidate.id === entry.id)
        if (reviewed == null || reviewed.contract !== entry.contract || reviewed.fixture !== entry.fixture
            || reviewed.resolutionInputSha256 !== resolutionInputDigest(entry)) {
          fail('FCR020_BASELINE_INTEGRITY', `${entry.id} reviewed graph authority input is stale`)
        }
      }
    }
    return {
      root,
      manifest,
      artifacts,
      policy: baselinePolicy,
      manifestSha256: sha256(fs.readFileSync(manifestPath))
    }
  } finally {
    releasePublicationLock(lock)
  }
}

function runLockedCases(policy, artifacts, expectedMetadata, toolchain, snapshot = null) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-rust-reviewed-resolution-'))
  const verified = new Map()
  try {
    for (const entry of policy.dependencyResolution.cases) {
      console.log(`[fresh-cargo-resolution] verify reviewed: ${entry.id}`)
      const caseRoot = path.join(root, 'cases', entry.id)
      fs.cpSync(snapshotFixtureRoot(snapshot, entry), caseRoot, { recursive: true })
      assertNoAncestorCargoConfiguration(caseRoot, caseRoot)
      fs.rmSync(path.join(caseRoot, 'target'), { recursive: true, force: true })
      fs.writeFileSync(path.join(caseRoot, 'Cargo.lock'), artifacts.get(entry.id).lock)
      const cargoHome = path.join(root, 'cargo-homes', entry.id)
      const env = cargoEnvironment(cargoHome, path.join(root, 'targets', entry.id), toolchain)
      const replacements = [[root, '<reviewed-resolution>'], [repoRoot, '<repo>']]
      runCommand(toolchain.cargo, ['fetch', '--locked', '--quiet'], { cwd: caseRoot, env, label: `${entry.id} reviewed cargo fetch`, replacements, id: 'FCR030_OFFLINE_CACHE_MISS' })
      const metadataResult = runCommand(toolchain.cargo, ['metadata', '--frozen', '--format-version', '1'], { cwd: caseRoot, env, label: `${entry.id} frozen Cargo metadata`, replacements })
      const metadata = jsonBytes(normalizeMetadata(JSON.parse(metadataResult.stdout), entry, policy))
      if (!metadata.equals(expectedMetadata.get(entry.id).metadata)) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `${entry.id} frozen metadata differs from the reviewed graph`)
      runCommand(toolchain.cargo, ['check', '--frozen', '--quiet'], { cwd: caseRoot, env, label: `${entry.id} frozen cargo check`, replacements })
      runCommand(toolchain.cargo, ['test', '--frozen', '--quiet'], { cwd: caseRoot, env, label: `${entry.id} frozen cargo test`, replacements })
      const lock = fs.readFileSync(path.join(caseRoot, 'Cargo.lock'))
      if (!lock.equals(artifacts.get(entry.id).lock)) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `${entry.id} Cargo changed the reviewed lock`)
      verified.set(entry.id, { lock, metadata })
    }
    return verified
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

function runFreshPass(policy, passIndex, toolchain, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), `reflaxe-rust-live-resolution-${passIndex}-`))
  const artifacts = new Map()
  try {
    for (const entry of policy.dependencyResolution.cases) {
      console.log(`[fresh-cargo-resolution] live ${options.upperEdge ? 'upper-edge' : 'fallback'} pass ${passIndex}/${policy.dependencyResolution.observationRepeatRuns}: ${entry.id}`)
      const caseRoot = path.join(root, 'cases', entry.id)
      fs.cpSync(snapshotFixtureRoot(options.snapshot, entry), caseRoot, { recursive: true })
      assertNoAncestorCargoConfiguration(caseRoot, caseRoot)
      fs.rmSync(path.join(caseRoot, 'Cargo.lock'), { force: true })
      fs.rmSync(path.join(caseRoot, 'target'), { recursive: true, force: true })
      const env = cargoEnvironment(path.join(root, 'cargo-homes', entry.id), path.join(root, 'targets', entry.id), toolchain)
      const replacements = [[root, '<live-resolution>'], [repoRoot, '<repo>']]
      const configArgs = options.upperEdge ? ['--config', 'resolver.incompatible-rust-versions="allow"'] : []
      runCommand(toolchain.cargo, ['generate-lockfile', '--quiet', ...configArgs], { cwd: caseRoot, env, label: `${entry.id} live lockfile generation`, replacements, id: options.upperEdge ? 'FCR103_UPPER_EDGE_INCOMPATIBLE_AVAILABLE' : 'FCR102_OBSERVATION_INCOMPATIBLE' })
      const metadataResult = runCommand(toolchain.cargo, ['metadata', '--locked', '--format-version', '1', ...configArgs], { cwd: caseRoot, env, label: `${entry.id} live Cargo metadata`, replacements, id: options.upperEdge ? 'FCR103_UPPER_EDGE_INCOMPATIBLE_AVAILABLE' : 'FCR102_OBSERVATION_INCOMPATIBLE' })
      const metadata = jsonBytes(normalizeMetadata(JSON.parse(metadataResult.stdout), entry, policy, {
        allowIncompatible: options.upperEdge,
        incompatibleRustVersions: options.upperEdge ? 'allow' : policy.dependencyResolution.incompatibleRustVersions
      }))
      if (!options.upperEdge) {
        runCommand(toolchain.cargo, ['check', '--locked', '--quiet'], { cwd: caseRoot, env, label: `${entry.id} live cargo check`, replacements, id: 'FCR102_OBSERVATION_INCOMPATIBLE' })
        runCommand(toolchain.cargo, ['test', '--locked', '--quiet'], { cwd: caseRoot, env, label: `${entry.id} live cargo test`, replacements, id: 'FCR102_OBSERVATION_INCOMPATIBLE' })
      }
      artifacts.set(entry.id, { lock: fs.readFileSync(path.join(caseRoot, 'Cargo.lock')), metadata })
    }
    return artifacts
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

function compareArtifactMaps(policy, left, right, id) {
  for (const entry of policy.dependencyResolution.cases) {
    for (const field of ['lock', 'metadata']) if (!left.get(entry.id)[field].equals(right.get(entry.id)[field])) fail(id, `${entry.id} ${field} changed between independent passes`)
  }
}

function artifactSetDigest(policy, artifacts) {
  return sha256(Buffer.concat(policy.dependencyResolution.cases.flatMap((entry) => {
    const artifact = artifacts.get(entry.id)
    return [artifact.lock, artifact.metadata]
  })))
}

function parseLock(bytes) {
  const packages = new Map()
  const source = bytes.toString('utf8')
  const header = source.split(/^\[\[package\]\]\s*$/m)[0]
  const headerLines = header.split(/\r?\n/).map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('#'))
  if (headerLines.length !== 1 || !/^version = [0-9]+$/.test(headerLines[0])) {
    fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', 'Cargo.lock contains an unknown top-level field')
  }
  const blocks = source.split(/^\[\[package\]\]\s*$/m).slice(1)
  for (const block of blocks) {
    const fields = new Map()
    const lines = block.split(/\r?\n/)
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index].trim()
      if (line.length === 0 || line.startsWith('#')) continue
      const scalar = /^(name|version|source|checksum) = "([^"]*)"$/.exec(line)
      if (scalar != null) {
        if (fields.has(scalar[1])) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `Cargo.lock package repeats field ${scalar[1]}`)
        fields.set(scalar[1], scalar[2])
        continue
      }
      if (line === 'dependencies = [') {
        if (fields.has('dependencies')) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', 'Cargo.lock package repeats dependencies')
        const dependencies = []
        let closed = false
        for (index += 1; index < lines.length; index += 1) {
          const dependencyLine = lines[index].trim()
          if (dependencyLine === ']') {
            closed = true
            break
          }
          const dependency = /^"([^"]+)",$/.exec(dependencyLine)
          if (dependency == null) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `Cargo.lock contains an unknown dependency entry: ${dependencyLine}`)
          dependencies.push(dependency[1])
        }
        if (!closed) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', 'Cargo.lock dependencies array is not closed')
        fields.set('dependencies', dependencies)
        continue
      }
      fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `Cargo.lock contains an unknown package field: ${line}`)
    }
    const name = fields.get('name')
    const version = fields.get('version')
    const packageSource = fields.get('source') || 'path'
    if (name == null || version == null) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', 'Cargo.lock package lacks name or version')
    const identity = `${name}@${version}:${packageSource}`
    if (packages.has(identity)) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `Cargo.lock repeats package identity ${identity}`)
    packages.set(identity, {
      identity,
      name,
      version,
      source: packageSource,
      checksum: fields.get('checksum') || null,
      dependencies: fields.get('dependencies') || []
    })
  }
  return { format: lockfileFormat(bytes), packages }
}

function assertExactObject(value, allowedKeys, owner, id = 'FCR202_ADMISSION_UNCLASSIFIED_CHANGE') {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    fail(id, `${owner} must be an object`)
  }
  const unknown = Object.keys(value).filter((key) => !allowedKeys.includes(key))
  const missing = allowedKeys.filter((key) => !Object.hasOwn(value, key))
  if (unknown.length > 0) fail(id, `${owner} contains unknown field(s): ${unknown.sort(compareText).join(', ')}`)
  if (missing.length > 0) fail(id, `${owner} lacks field(s): ${missing.sort(compareText).join(', ')}`)
}

function assertArray(value, owner) {
  if (!Array.isArray(value)) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `${owner} must be an array`)
}

function assertNormalizedMetadataShape(metadata, owner) {
  assertExactObject(metadata, [
    'schemaVersion', 'caseId', 'contract', 'fixture', 'minimumSupportedRust', 'resolverVersion',
    'incompatibleRustVersions', 'rootPackage', 'workspaceMembers', 'workspaceDefaultMembers',
    'resolvedGraph', 'packages'
  ], owner)
  assertArray(metadata.workspaceMembers, `${owner}.workspaceMembers`)
  assertArray(metadata.workspaceDefaultMembers, `${owner}.workspaceDefaultMembers`)
  assertArray(metadata.packages, `${owner}.packages`)
  const packageIds = new Set()
  for (const [index, pkg] of metadata.packages.entries()) {
    const packageOwner = `${owner}.packages[${index}]`
    assertExactObject(pkg, ['id', 'name', 'version', 'source', 'rustVersion', 'enabledFeatures', 'dependencies'], packageOwner)
    if (packageIds.has(pkg.id)) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `${owner} repeats package id ${pkg.id}`)
    packageIds.add(pkg.id)
    assertArray(pkg.enabledFeatures, `${packageOwner}.enabledFeatures`)
    assertArray(pkg.dependencies, `${packageOwner}.dependencies`)
    for (const [dependencyIndex, dependency] of pkg.dependencies.entries()) {
      assertExactObject(dependency, [
        'name', 'rename', 'requirement', 'source', 'kind', 'optional', 'usesDefaultFeatures',
        'features', 'target'
      ], `${packageOwner}.dependencies[${dependencyIndex}]`)
      assertArray(dependency.features, `${packageOwner}.dependencies[${dependencyIndex}].features`)
    }
  }
  assertExactObject(metadata.resolvedGraph, ['root', 'nodes'], `${owner}.resolvedGraph`)
  assertArray(metadata.resolvedGraph.nodes, `${owner}.resolvedGraph.nodes`)
  const nodeIds = new Set()
  for (const [index, node] of metadata.resolvedGraph.nodes.entries()) {
    const nodeOwner = `${owner}.resolvedGraph.nodes[${index}]`
    assertExactObject(node, ['id', 'enabledFeatures', 'dependencies'], nodeOwner)
    if (nodeIds.has(node.id)) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `${owner} repeats resolved node id ${node.id}`)
    nodeIds.add(node.id)
    assertArray(node.enabledFeatures, `${nodeOwner}.enabledFeatures`)
    assertArray(node.dependencies, `${nodeOwner}.dependencies`)
    for (const [dependencyIndex, dependency] of node.dependencies.entries()) {
      const dependencyOwner = `${nodeOwner}.dependencies[${dependencyIndex}]`
      assertExactObject(dependency, ['name', 'package', 'kinds'], dependencyOwner)
      assertArray(dependency.kinds, `${dependencyOwner}.kinds`)
      for (const [kindIndex, kind] of dependency.kinds.entries()) {
        assertExactObject(kind, ['kind', 'target'], `${dependencyOwner}.kinds[${kindIndex}]`)
      }
    }
  }
  if (metadata.schemaVersion === 2 && !jsonBytes(metadata).equals(jsonBytes(canonicalNormalizedMetadata(metadata)))) {
    fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `${owner} is not in canonical byte order`)
  }
}

function canonicalNormalizedMetadata(metadata) {
  return {
    schemaVersion: metadata.schemaVersion,
    caseId: metadata.caseId,
    contract: metadata.contract,
    fixture: metadata.fixture,
    minimumSupportedRust: metadata.minimumSupportedRust,
    resolverVersion: metadata.resolverVersion,
    incompatibleRustVersions: metadata.incompatibleRustVersions,
    rootPackage: metadata.rootPackage,
    workspaceMembers: [...metadata.workspaceMembers].sort(compareText),
    workspaceDefaultMembers: [...metadata.workspaceDefaultMembers].sort(compareText),
    resolvedGraph: {
      root: metadata.resolvedGraph.root,
      nodes: metadata.resolvedGraph.nodes.map((node) => ({
        id: node.id,
        enabledFeatures: [...node.enabledFeatures].sort(compareText),
        dependencies: node.dependencies.map((dependency) => ({
          name: dependency.name,
          package: dependency.package,
          kinds: dependency.kinds.map((kind) => ({ kind: kind.kind, target: kind.target }))
            .sort((left, right) => compareText(JSON.stringify(left), JSON.stringify(right)))
        })).sort((left, right) => compareText(JSON.stringify(left), JSON.stringify(right)))
      })).sort((left, right) => compareText(left.id, right.id))
    },
    packages: metadata.packages.map((pkg) => ({
      id: pkg.id,
      name: pkg.name,
      version: pkg.version,
      source: pkg.source,
      rustVersion: pkg.rustVersion,
      enabledFeatures: [...pkg.enabledFeatures].sort(compareText),
      dependencies: pkg.dependencies.map((dependency) => ({
        name: dependency.name,
        rename: dependency.rename,
        requirement: dependency.requirement,
        source: dependency.source,
        kind: dependency.kind,
        optional: dependency.optional,
        usesDefaultFeatures: dependency.usesDefaultFeatures,
        features: [...dependency.features].sort(compareText),
        target: dependency.target
      })).sort((left, right) => compareText(JSON.stringify(left), JSON.stringify(right)))
    })).sort((left, right) => compareText(left.id, right.id))
  }
}

function compareValues(changes, caseId, category, subject, field, left, right) {
  if (JSON.stringify(left) !== JSON.stringify(right)) changes.push({ caseId, category, subject, field, old: left, new: right })
}

function sortedValues(values) {
  return [...values].sort((left, right) => compareText(JSON.stringify(left), JSON.stringify(right)))
}

function sortedResolvedDependencies(values, idMap = new Map()) {
  return sortedValues(values.map((dependency) => ({
    ...dependency,
    package: idMap.get(dependency.package) || dependency.package,
    kinds: sortedValues(dependency.kinds)
  })))
}

function logicalPackagePairs(leftValues, rightValues) {
  const pairs = []
  const leftRemaining = new Set(leftValues.map((value) => value.id || value.identity))
  const rightRemaining = new Set(rightValues.map((value) => value.id || value.identity))
  for (const left of leftValues) {
    const leftId = left.id || left.identity
    const exact = rightValues.find((right) => (right.id || right.identity) === leftId)
    if (exact != null) {
      pairs.push([left, exact])
      leftRemaining.delete(leftId)
      rightRemaining.delete(exact.id || exact.identity)
    }
  }
  for (const left of leftValues.filter((value) => leftRemaining.has(value.id || value.identity))) {
    const candidates = rightValues.filter((right) => rightRemaining.has(right.id || right.identity)
      && right.name === left.name)
    const reverseCandidates = leftValues.filter((other) => leftRemaining.has(other.id || other.identity)
      && other.name === left.name)
    if (candidates.length !== 1 || reverseCandidates.length !== 1) continue
    const right = candidates[0]
    pairs.push([left, right])
    leftRemaining.delete(left.id || left.identity)
    rightRemaining.delete(right.id || right.identity)
  }
  return {
    pairs,
    leftOnly: leftValues.filter((value) => leftRemaining.has(value.id || value.identity)),
    rightOnly: rightValues.filter((value) => rightRemaining.has(value.id || value.identity))
  }
}

function remapNode(node, idMap) {
  return {
    ...node,
    dependencies: sortedResolvedDependencies(node.dependencies, idMap)
  }
}

function classifyCase(entry, before, after, policy) {
  const changes = []
  const beforeLock = parseLock(before.lock)
  const afterLock = parseLock(after.lock)
  compareValues(changes, entry.id, 'lock-format', entry.id, 'lockfileFormat', beforeLock.format, afterLock.format)
  const lockIds = new Set([...beforeLock.packages.keys(), ...afterLock.packages.keys()])
  const removed = []
  const added = []
  for (const id of [...lockIds].sort(compareText)) {
    const left = beforeLock.packages.get(id)
    const right = afterLock.packages.get(id)
    if (left == null) added.push(right)
    else if (right == null) removed.push(left)
    else {
      if (left.checksum !== right.checksum) changes.push({ caseId: entry.id, category: 'package-checksum-changed', subject: id, field: 'checksum', old: left.checksum, new: right.checksum })
      compareValues(changes, entry.id, 'package-lock-dependencies-changed', id, 'dependencies', left.dependencies, right.dependencies)
    }
  }
  const consumedAdded = new Set()
  const consumedRemoved = new Set()
  for (const oldPackage of removed) {
    const candidates = added.filter((candidate) => candidate.name === oldPackage.name
      && candidate.source === oldPackage.source && !consumedAdded.has(candidate.identity))
    const oldCandidates = removed.filter((candidate) => candidate.name === oldPackage.name
      && candidate.source === oldPackage.source)
    if (candidates.length !== 1 || oldCandidates.length !== 1) continue
    const newPackage = candidates[0]
    consumedAdded.add(newPackage.identity)
    consumedRemoved.add(oldPackage.identity)
    changes.push({
      caseId: entry.id,
      category: 'package-version-changed',
      subject: `${oldPackage.name}:${oldPackage.source}`,
      field: 'version',
      old: oldPackage.version,
      new: newPackage.version
    })
    compareValues(changes, entry.id, 'package-version-checksum-changed', `${oldPackage.name}:${oldPackage.source}`, 'checksum', oldPackage.checksum, newPackage.checksum)
  }
  for (const pkg of removed.filter((candidate) => !consumedRemoved.has(candidate.identity))) {
    changes.push({ caseId: entry.id, category: 'package-removed', subject: pkg.identity, field: 'identity', old: pkg.identity, new: null })
  }
  for (const pkg of added.filter((candidate) => !consumedAdded.has(candidate.identity))) {
    changes.push({ caseId: entry.id, category: 'package-added', subject: pkg.identity, field: 'identity', old: null, new: pkg.identity })
  }
  const oldMeta = parseJsonBytes(before.metadata, `${entry.id} reviewed metadata`, 'FCR202_ADMISSION_UNCLASSIFIED_CHANGE')
  const newMeta = parseJsonBytes(after.metadata, `${entry.id} candidate metadata`, 'FCR202_ADMISSION_UNCLASSIFIED_CHANGE')
  assertNormalizedMetadataShape(oldMeta, `${entry.id} reviewed metadata`)
  assertNormalizedMetadataShape(newMeta, `${entry.id} candidate metadata`)
  for (const field of ['schemaVersion', 'caseId', 'contract', 'fixture', 'minimumSupportedRust', 'resolverVersion', 'incompatibleRustVersions', 'rootPackage', 'workspaceMembers', 'workspaceDefaultMembers']) {
    compareValues(changes, entry.id, field.startsWith('workspace') || field === 'rootPackage' ? 'topology-changed' : 'authority-input-changed', entry.id, field, oldMeta[field], newMeta[field])
  }
  const metadataPairs = logicalPackagePairs(oldMeta.packages, newMeta.packages)
  const newToOldIds = new Map(metadataPairs.pairs.map(([left, right]) => [right.id, left.id]))
  for (const [left, right] of metadataPairs.pairs) {
    const subject = left.id === right.id ? left.id : `${left.name}:${left.source}->${right.source}`
    for (const field of ['name', 'version', 'source']) {
      compareValues(changes, entry.id, 'metadata-package-identity-changed', subject, field, left[field], right[field])
    }
    compareValues(changes, entry.id, 'declared-msrv-changed', subject, 'rustVersion', left.rustVersion, right.rustVersion)
    compareValues(changes, entry.id, 'enabled-features-changed', subject, 'enabledFeatures', sortedValues(left.enabledFeatures), sortedValues(right.enabledFeatures))
    compareValues(changes, entry.id, 'declared-dependencies-changed', subject, 'dependencies', sortedValues(left.dependencies), sortedValues(right.dependencies))
  }
  for (const pkg of metadataPairs.leftOnly) {
    changes.push({ caseId: entry.id, category: 'metadata-package-removed', subject: pkg.id, field: 'id', old: pkg.id, new: null })
  }
  for (const pkg of metadataPairs.rightOnly) {
    changes.push({ caseId: entry.id, category: 'metadata-package-added', subject: pkg.id, field: 'id', old: null, new: pkg.id })
  }
  const oldNodes = new Map(oldMeta.resolvedGraph.nodes.map((node) => [node.id, node]))
  const newNodes = new Map(newMeta.resolvedGraph.nodes.map((node) => [node.id, node]))
  compareValues(changes, entry.id, 'topology-changed', entry.id, 'resolvedGraph.root', oldMeta.resolvedGraph.root, newToOldIds.get(newMeta.resolvedGraph.root) || newMeta.resolvedGraph.root)
  for (const [leftPackage, rightPackage] of metadataPairs.pairs) {
    const left = oldNodes.get(leftPackage.id)
    const right = newNodes.get(rightPackage.id)
    if (left == null || right == null) continue
    compareValues(changes, entry.id, 'enabled-features-changed', leftPackage.id, 'resolvedEnabledFeatures', sortedValues(left.enabledFeatures), sortedValues(right.enabledFeatures))
    compareValues(changes, entry.id, 'topology-edges-changed', leftPackage.id, 'dependencies', sortedResolvedDependencies(left.dependencies), remapNode(right, newToOldIds).dependencies)
  }
  for (const pkg of metadataPairs.leftOnly) {
    if (oldNodes.has(pkg.id)) changes.push({ caseId: entry.id, category: 'topology-node-removed', subject: pkg.id, field: 'node', old: pkg.id, new: null })
  }
  for (const pkg of metadataPairs.rightOnly) {
    if (newNodes.has(pkg.id)) changes.push({ caseId: entry.id, category: 'topology-node-added', subject: pkg.id, field: 'node', old: null, new: pkg.id })
  }
  if (changes.length === 0 && (!before.lock.equals(after.lock) || !before.metadata.equals(after.metadata))) changes.push({ caseId: entry.id, category: 'serialization-changed', subject: entry.id, field: 'bytes', old: sha256(Buffer.concat([before.lock, before.metadata])), new: sha256(Buffer.concat([after.lock, after.metadata])) })
  return changes
}

function classifyArtifacts(policy, baselineArtifacts, candidateArtifacts, options = {}) {
  const baselinePolicy = options.baselinePolicy || policy
  const baselineEntries = new Map(baselinePolicy.dependencyResolution.cases.map((entry) => [entry.id, entry]))
  const currentEntries = new Map(policy.dependencyResolution.cases.map((entry) => [entry.id, entry]))
  const changes = []
  for (const id of [...new Set([...baselineEntries.keys(), ...currentEntries.keys()])].sort(compareText)) {
    const beforeEntry = baselineEntries.get(id)
    const afterEntry = currentEntries.get(id)
    if (beforeEntry == null) {
      changes.push({
        caseId: id,
        category: 'authority-input-changed',
        subject: id,
        field: 'case',
        old: null,
        new: { contract: afterEntry.contract, fixture: afterEntry.fixture }
      })
      continue
    }
    if (afterEntry == null) {
      changes.push({
        caseId: id,
        category: 'authority-input-changed',
        subject: id,
        field: 'case',
        old: { contract: beforeEntry.contract, fixture: beforeEntry.fixture },
        new: null
      })
      continue
    }
    changes.push(...classifyCase(afterEntry, baselineArtifacts.get(id), candidateArtifacts.get(id), policy))
  }
  if (options.baselineManifest != null) {
    const currentPolicySha256 = options.currentPolicySha256 || policyDigest()
    const currentInputDigests = options.currentInputDigests || new Map(
      policy.dependencyResolution.cases.map((entry) => [entry.id, resolutionInputDigest(entry)]))
    compareValues(changes, '<policy>', 'authority-input-changed', '<policy>', 'policySha256', options.baselineManifest.policySha256, currentPolicySha256)
    const oldInputs = new Map(options.baselineManifest.cases.map((entry) => [entry.id, entry.resolutionInputSha256]))
    for (const entry of policy.dependencyResolution.cases) {
      compareValues(changes, entry.id, 'authority-input-changed', entry.id, 'resolutionInputSha256', oldInputs.get(entry.id) || null, currentInputDigests.get(entry.id))
    }
  }
  changes.sort((left, right) => compareText(JSON.stringify(left), JSON.stringify(right)))
  const checksumIncident = changes.some((change) => change.category === 'package-checksum-changed')
  const unclassifiedSerialization = changes.some((change) => change.category === 'serialization-changed')
  return {
    schemaVersion: 1,
    relation: changes.length === 0 ? 'match' : 'drift',
    admissible: !checksumIncident && !unclassifiedSerialization,
    changes
  }
}

function safeOutputDirectory(value, lane = 'minimum') {
  const evidenceRoot = path.join(repoRoot, '.cache', 'fresh-cargo-resolution')
  const resolved = path.resolve(repoRoot, value || path.join(evidenceRoot, lane))
  const relative = path.relative(evidenceRoot, resolved)
  if (relative.length === 0 || relative.startsWith('..') || path.isAbsolute(relative)) fail('FCR900_USAGE', 'evidence output directory must be below .cache/fresh-cargo-resolution')
  const components = path.relative(repoRoot, resolved).split(path.sep).filter((part) => part.length > 0)
  let current = repoRoot
  for (const component of components) {
    current = path.join(current, component)
    let stat = null
    try {
      stat = fs.lstatSync(current)
    } catch (error) {
      if (error.code === 'ENOENT') break
      throw error
    }
    if (stat.isSymbolicLink()) fail('FCR900_USAGE', 'evidence output directory must not contain symlinked path components')
    if (!stat.isDirectory()) fail('FCR900_USAGE', 'evidence output path components must be directories')
  }
  return resolved
}

function ownedOutputDirectory(args, option, lane) {
  const expected = path.join(repoRoot, '.cache', 'fresh-cargo-resolution', lane)
  const requested = path.resolve(repoRoot, argumentValue(args, option, expected))
  if (requested !== expected) fail('FCR900_USAGE', `${option} must use the mode-owned path ${path.relative(repoRoot, expected)}`)
  return safeOutputDirectory(expected, lane)
}

function candidateTreeDigest(root) {
  const rootStat = fs.lstatSync(root)
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) {
    fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate root must be a real directory')
  }
  const hash = crypto.createHash('sha256')
  const files = []
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((left, right) => compareText(left.name, right.name))) {
      const full = path.join(directory, entry.name)
      if (entry.isSymbolicLink()) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate tree must not contain symlinks')
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile()) files.push(full)
      else fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate tree must contain only directories and regular files')
    }
  }
  visit(root)
  for (const file of files) {
    const relative = path.relative(root, file).split(path.sep).join('/')
    const bytes = fs.readFileSync(file)
    hash.update(`${relative}\0${bytes.length}\0`)
    hash.update(bytes)
  }
  return hash.digest('hex')
}

function captureCandidateSnapshot(candidateDir, reviewedDigest) {
  const sourceDigest = candidateTreeDigest(candidateDir)
  if (sourceDigest !== reviewedDigest) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate tree digest differs from --candidate-sha256')
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-rust-admission-candidate-'))
  const snapshot = path.join(root, 'candidate')
  try {
    fs.cpSync(candidateDir, snapshot, { recursive: true, errorOnExist: true, force: false })
    if (candidateTreeDigest(snapshot) !== reviewedDigest) {
      fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate changed while its admission snapshot was captured')
    }
    return { root, candidateDir: snapshot }
  } catch (error) {
    fs.rmSync(root, { recursive: true, force: true })
    throw error
  }
}

function assertCandidateFileInventory(policy, candidateDir, observation) {
  const expected = new Set(['classification.json', 'observation.json'])
  for (const entry of policy.dependencyResolution.cases) {
    expected.add(`fallback/${entry.id}/Cargo.lock`)
    expected.add(`fallback/${entry.id}/metadata.json`)
    if (observation.upperEdge != null) {
      expected.add(`upper-edge/${entry.id}/Cargo.lock`)
      expected.add(`upper-edge/${entry.id}/metadata.json`)
    }
  }
  const actual = new Set()
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((left, right) => compareText(left.name, right.name))) {
      const full = path.join(directory, entry.name)
      if (entry.isSymbolicLink()) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate tree must not contain symlinks')
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile()) actual.add(path.relative(candidateDir, full).split(path.sep).join('/'))
      else fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate tree must contain only directories and regular files')
    }
  }
  visit(candidateDir)
  const missing = [...expected].filter((entry) => !actual.has(entry))
  const extra = [...actual].filter((entry) => !expected.has(entry))
  if (missing.length > 0 || extra.length > 0) {
    fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `candidate file inventory differs (missing=${missing.sort(compareText).join(',') || 'none'}; extra=${extra.sort(compareText).join(',') || 'none'})`)
  }
}

function writeArtifactTree(policy, artifacts, root) {
  for (const entry of policy.dependencyResolution.cases) {
    const caseRoot = path.join(root, entry.id)
    fs.mkdirSync(caseRoot, { recursive: true })
    fs.writeFileSync(path.join(caseRoot, 'Cargo.lock'), artifacts.get(entry.id).lock)
    fs.writeFileSync(path.join(caseRoot, 'metadata.json'), artifacts.get(entry.id).metadata)
  }
}

function writeReviewedEvidence(policy, artifacts, toolchain, outDir, options) {
  fs.rmSync(outDir, { recursive: true, force: true })
  fs.mkdirSync(outDir, { recursive: true })
  writeArtifactTree(policy, artifacts, outDir)
  const summary = {
    schemaVersion: 2,
    mode: options.mode,
    baselineRelation: 'match',
    lane: options.lane,
    actualRustc: toolchain.rustcVersion,
    actualCargo: toolchain.cargoVersion,
    lockedMetadataPassed: true,
    lockedCheckPassed: true,
    lockedTestPassed: true,
    repeatabilityPassed: null,
    mutationRejected: options.mutationRejected,
    admissible: options.admissible,
    upperEdgeOnly: false
  }
  fs.writeFileSync(path.join(outDir, 'summary.json'), jsonBytes(summary))
}

function artifactDigests(policy, artifacts) {
  return policy.dependencyResolution.cases.map((entry) => ({
    id: entry.id,
    lockSha256: sha256(artifacts.get(entry.id).lock),
    metadataSha256: sha256(artifacts.get(entry.id).metadata)
  }))
}

function writeObservation(policy, baseline, fallback, upperEdge, classification, toolchain, outDir, passDigests, snapshot) {
  fs.rmSync(outDir, { recursive: true, force: true })
  fs.mkdirSync(outDir, { recursive: true })
  writeArtifactTree(policy, fallback, path.join(outDir, 'fallback'))
  if (upperEdge != null) writeArtifactTree(policy, upperEdge, path.join(outDir, 'upper-edge'))
  fs.writeFileSync(path.join(outDir, 'classification.json'), jsonBytes(classification))
  const observation = {
    schemaVersion: observationSchemaVersion,
    mode: 'observe-live',
    baseManifestSha256: baseline.manifestSha256,
    policySha256: sha256(snapshot.policyBytes),
    normalizationSchemaVersion,
    actualRustc: toolchain.rustcVersion,
    actualCargo: toolchain.cargoVersion,
    resolutionInputs: policy.dependencyResolution.cases.map((entry) => ({
      id: entry.id,
      sha256: snapshot.inputDigests.get(entry.id)
    })),
    passDigests,
    fallback: artifactDigests(policy, fallback),
    upperEdge: upperEdge == null ? null : artifactDigests(policy, upperEdge),
    classificationSha256: sha256(jsonBytes(classification)),
    baselineRelation: classification.relation,
    admissible: classification.admissible,
    lockedMetadataPassed: true,
    lockedCheckPassed: true,
    lockedTestPassed: true,
    repeatabilityPassed: true,
    mutationRejected: true,
    upperEdgeOnly: false
  }
  fs.writeFileSync(path.join(outDir, 'observation.json'), jsonBytes(observation))
}

function assertDigest(value, owner) {
  if (!/^[0-9a-f]{64}$/.test(value || '')) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `${owner} must be a SHA-256 digest`)
}

function assertDigestEntries(value, owner) {
  if (!Array.isArray(value)) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `${owner} must be an array`)
  const ids = new Set()
  for (const [index, entry] of value.entries()) {
    assertExactObject(entry, ['id', 'lockSha256', 'metadataSha256'], `${owner}[${index}]`)
    if (ids.has(entry.id)) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `${owner} repeats case ${entry.id}`)
    ids.add(entry.id)
    assertDigest(entry.lockSha256, `${owner}[${index}].lockSha256`)
    assertDigest(entry.metadataSha256, `${owner}[${index}].metadataSha256`)
  }
}

function assertObservationShape(policy, observation, classification) {
  assertExactObject(observation, [
    'schemaVersion', 'mode', 'baseManifestSha256', 'policySha256', 'normalizationSchemaVersion',
    'actualRustc', 'actualCargo', 'resolutionInputs', 'passDigests', 'fallback', 'upperEdge',
    'classificationSha256', 'baselineRelation', 'admissible', 'lockedMetadataPassed',
    'lockedCheckPassed', 'lockedTestPassed', 'repeatabilityPassed', 'mutationRejected',
    'upperEdgeOnly'
  ], 'candidate observation')
  assertDigest(observation.baseManifestSha256, 'candidate observation.baseManifestSha256')
  assertDigest(observation.policySha256, 'candidate observation.policySha256')
  assertDigest(observation.classificationSha256, 'candidate observation.classificationSha256')
  if (!Array.isArray(observation.resolutionInputs)) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate resolutionInputs must be an array')
  const inputIds = new Set()
  for (const [index, input] of observation.resolutionInputs.entries()) {
    assertExactObject(input, ['id', 'sha256'], `candidate resolutionInputs[${index}]`)
    if (inputIds.has(input.id)) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `candidate repeats resolution input ${input.id}`)
    inputIds.add(input.id)
    assertDigest(input.sha256, `candidate resolutionInputs[${index}].sha256`)
  }
  assertExactObject(observation.passDigests, ['fallback', 'upperEdge'], 'candidate passDigests')
  for (const owner of ['fallback', 'upperEdge']) {
    if (!Array.isArray(observation.passDigests[owner])) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `candidate passDigests.${owner} must be an array`)
    for (const [index, digest] of observation.passDigests[owner].entries()) assertDigest(digest, `candidate passDigests.${owner}[${index}]`)
  }
  assertDigestEntries(observation.fallback, 'candidate fallback')
  if (observation.upperEdge != null) assertDigestEntries(observation.upperEdge, 'candidate upperEdge')
  assertExactObject(classification, ['schemaVersion', 'relation', 'admissible', 'changes'], 'candidate classification')
  if (classification.schemaVersion !== 1) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate classification schema is invalid')
  if (!Array.isArray(classification.changes)) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate classification changes must be an array')
  const knownCategories = new Set([
    'lock-format', 'package-checksum-changed', 'package-lock-dependencies-changed',
    'package-version-changed', 'package-version-checksum-changed', 'package-removed', 'package-added',
    'topology-changed', 'authority-input-changed', 'metadata-package-added',
    'metadata-package-removed', 'metadata-package-identity-changed', 'declared-msrv-changed',
    'enabled-features-changed', 'declared-dependencies-changed', 'topology-node-added',
    'topology-node-removed', 'topology-edges-changed', 'serialization-changed'
  ])
  for (const [index, change] of classification.changes.entries()) {
    assertExactObject(change, ['caseId', 'category', 'subject', 'field', 'old', 'new'], `candidate classification changes[${index}]`)
    if (!knownCategories.has(change.category)) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `candidate classification contains unknown category ${change.category}`)
  }
  if (!['match', 'drift'].includes(classification.relation)
      || classification.relation !== (classification.changes.length === 0 ? 'match' : 'drift')) {
    fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate classification relation does not match its changes')
  }
  if (observation.baselineRelation !== classification.relation || observation.admissible !== classification.admissible) {
    fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate observation does not match its classification')
  }
  if (observation.normalizationSchemaVersion !== normalizationSchemaVersion) {
    fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate normalization schema is invalid')
  }
  if (typeof observation.actualRustc !== 'string' || typeof observation.actualCargo !== 'string') {
    fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate toolchain versions must be strings')
  }
  const expectedAdmissible = !classification.changes.some((change) => change.category === 'package-checksum-changed'
    || change.category === 'serialization-changed')
  if (classification.admissible !== expectedAdmissible) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate classification has an invalid admissible decision')
  if (observation.passDigests.fallback.length !== policy.dependencyResolution.observationRepeatRuns) {
    fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `candidate must contain ${policy.dependencyResolution.observationRepeatRuns} fallback pass digests`)
  }
  if (![0, policy.dependencyResolution.observationRepeatRuns].includes(observation.passDigests.upperEdge.length)) {
    fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `candidate must contain zero or ${policy.dependencyResolution.observationRepeatRuns} upper-edge pass digests`)
  }
  for (const field of ['lockedMetadataPassed', 'lockedCheckPassed', 'lockedTestPassed', 'repeatabilityPassed', 'mutationRejected']) {
    if (observation[field] !== true) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `candidate observation ${field} must be true`)
  }
  if (observation.upperEdgeOnly !== false) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'an upper-edge-only candidate cannot be admitted')
}

function runMutationProbe(policy, toolchain = loadSelectedToolchain()) {
  const unsupported = nextRustMinor(toolchain.rustcVersion)
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-rust-msrv-mutation-'))
  try {
    fs.mkdirSync(path.join(root, 'src'), { recursive: true })
    fs.mkdirSync(path.join(root, 'msrv-probe', 'src'), { recursive: true })
    fs.writeFileSync(path.join(root, 'Cargo.toml'), `[package]\nname = "msrv_mutation_root"\nversion = "0.1.0"\nedition = "2021"\nrust-version = "${policy.minimumSupportedRust}"\nresolver = "${policy.dependencyResolution.resolverVersion}"\n\n[dependencies]\nmsrv_probe = { version = "1", path = "msrv-probe" }\n`)
    fs.writeFileSync(path.join(root, 'src', 'main.rs'), 'fn main() { assert_eq!(msrv_probe::value(), 1); }\n')
    fs.writeFileSync(path.join(root, 'msrv-probe', 'Cargo.toml'), `[package]\nname = "msrv_probe"\nversion = "1.1.0"\nedition = "2021"\nrust-version = "${unsupported}"\n\n[lib]\npath = "src/lib.rs"\n`)
    fs.writeFileSync(path.join(root, 'msrv-probe', 'src', 'lib.rs'), 'pub fn value() -> i32 { 1 }\n')
    assertNoAncestorCargoConfiguration(root, root)
    const env = cargoEnvironment(path.join(root, 'cargo-home'), path.join(root, 'target'), toolchain)
    const replacements = [[root, '<msrv-mutation>'], [repoRoot, '<repo>']]
    runCommand(toolchain.cargo, ['generate-lockfile', '--quiet'], { cwd: root, env, label: 'MSRV mutation lockfile generation', replacements })
    const result = runCommand(toolchain.cargo, ['check', '--locked', '--quiet'], { cwd: root, env, label: 'MSRV mutation cargo check', replacements, allowFailure: true })
    if (result.status === 0) fail('FCR102_OBSERVATION_INCOMPATIBLE', `Cargo accepted a dependency requiring unsupported rustc ${unsupported}`)
    const output = sanitizeOutput(`${result.stdout || ''}\n${result.stderr || ''}`, replacements)
    if (!output.includes('msrv_probe') || !output.includes(unsupported)) fail('FCR102_OBSERVATION_INCOMPATIBLE', `mutation failed without naming msrv_probe and rustc ${unsupported}`)
    console.log(`[fresh-cargo-resolution] incompatible dependency mutation rejected (required=${unsupported}, actual=${toolchain.rustcVersion})`)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

function verifyLane(policy, lane, toolchain) {
  if (!['minimum', 'current'].includes(lane)) fail('FCR900_USAGE', '--lane must be minimum or current')
  if (lane === 'minimum' && toolchain.rustcVersion !== policy.minimumSupportedRust) fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', `minimum lane resolved rustc ${toolchain.rustcVersion}; expected ${policy.minimumSupportedRust}`)
  if (compareRustVersions(toolchain.rustcVersion, policy.minimumSupportedRust) < 0) fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', `${lane} lane rustc ${toolchain.rustcVersion} is older than ${policy.minimumSupportedRust}`)
}

function runVerifyReviewed(policy, args) {
  const lane = argumentValue(args, '--lane')
  const toolchain = loadSelectedToolchain()
  verifyLane(policy, lane, toolchain)
  const baseline = checkBaseline(policy)
  const snapshot = captureAuthoritySnapshot(policy)
  try {
    verifyFixtureManifests(policy, snapshot)
    const verified = runLockedCases(policy, baseline.artifacts, baseline.artifacts, toolchain, snapshot)
    let mutationRejected = null
    if (lane === 'minimum') {
      runMutationProbe(policy, toolchain)
      mutationRejected = true
    }
    assertAuthoritySnapshotCurrent(policy, snapshot)
    writeReviewedEvidence(policy, verified, toolchain, ownedOutputDirectory(args, '--out-dir', `reviewed/${lane}`), {
      mode: 'verify-reviewed',
      lane,
      mutationRejected,
      admissible: true
    })
  } finally {
    fs.rmSync(snapshot.root, { recursive: true, force: true })
  }
  console.log(`[fresh-cargo-resolution] reviewed graph OK (lane=${lane}, rustc=${toolchain.rustcVersion}, cargo=${toolchain.cargoVersion})`)
}

function runObserveLive(policy, args) {
  const lane = argumentValue(args, '--lane')
  if (lane !== 'minimum') fail('FCR900_USAGE', 'live observation requires --lane minimum')
  const toolchain = loadSelectedToolchain()
  verifyLane(policy, lane, toolchain)
  const baseline = checkBaseline(policy, { allowCurrentAuthorityChange: true })
  const snapshot = captureAuthoritySnapshot(policy)
  try {
    verifyFixtureManifests(policy, snapshot)
    let fallback = null
    const fallbackPassDigests = []
    for (let index = 1; index <= policy.dependencyResolution.observationRepeatRuns; index += 1) {
      const candidate = runFreshPass(policy, index, toolchain, { snapshot })
      fallbackPassDigests.push(artifactSetDigest(policy, candidate))
      if (fallback == null) fallback = candidate
      else compareArtifactMaps(policy, fallback, candidate, 'FCR100_OBSERVATION_NONDETERMINISTIC')
    }
    let upperEdge = null
    const upperPassDigests = []
    if (args.includes('--include-upper-edge')) {
      for (let index = 1; index <= policy.dependencyResolution.observationRepeatRuns; index += 1) {
        const candidate = runFreshPass(policy, index, toolchain, { upperEdge: true, snapshot })
        upperPassDigests.push(artifactSetDigest(policy, candidate))
        if (upperEdge == null) upperEdge = candidate
        else compareArtifactMaps(policy, upperEdge, candidate, 'FCR100_OBSERVATION_NONDETERMINISTIC')
      }
    }
    runMutationProbe(policy, toolchain)
    const classification = classifyArtifacts(policy, baseline.artifacts, fallback, {
      baselinePolicy: baseline.policy,
      baselineManifest: baseline.manifest,
      currentPolicySha256: sha256(snapshot.policyBytes),
      currentInputDigests: snapshot.inputDigests
    })
    assertAuthoritySnapshotCurrent(policy, snapshot)
    const outDir = ownedOutputDirectory(args, '--out-dir', 'observation')
    writeObservation(policy, baseline, fallback, upperEdge, classification, toolchain, outDir, { fallback: fallbackPassDigests, upperEdge: upperPassDigests }, snapshot)
    const candidateSha256 = candidateTreeDigest(outDir)
    if (classification.relation === 'drift') fail('FCR101_OBSERVATION_DRIFT', `${classification.changes.length} reviewed dependency difference(s); candidate written to ${path.relative(repoRoot, outDir)}; candidate SHA-256 ${candidateSha256}`)
    console.log(`[fresh-cargo-resolution] live observation matches the reviewed graph; candidate SHA-256 ${candidateSha256}`)
  } finally {
    fs.rmSync(snapshot.root, { recursive: true, force: true })
  }
}

function verifyObservationIntegrity(policy, candidateDir, observation, classification, snapshot = null) {
  assertObservationShape(policy, observation, classification)
  if (observation.schemaVersion !== observationSchemaVersion || observation.mode !== 'observe-live') fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate observation schema or mode is invalid')
  const currentPolicySha256 = snapshot == null ? policyDigest() : sha256(snapshot.policyBytes)
  if (observation.policySha256 !== currentPolicySha256) fail('FCR200_ADMISSION_STALE_BASE', 'policy changed after observation')
  if (observation.classificationSha256 !== sha256(jsonBytes(classification))) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate classification digest does not match')
  function verifyArtifactSet(directory, digests, owner) {
    if (digests.length !== policy.dependencyResolution.cases.length) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `${owner} has the wrong number of cases`)
    const artifacts = artifactsFromDirectory(policy, path.join(candidateDir, directory), 'FCR201_ADMISSION_ARTIFACT_INTEGRITY')
    for (const entry of policy.dependencyResolution.cases) {
      const expected = digests.find((item) => item.id === entry.id)
      if (expected == null) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `${owner} lacks ${entry.id} digests`)
      const artifact = artifacts.get(entry.id)
      const metadata = parseJsonBytes(artifact.metadata, `${owner} ${entry.id} metadata`, 'FCR201_ADMISSION_ARTIFACT_INTEGRITY')
      assertNormalizedMetadataShape(metadata, `${owner} ${entry.id} metadata`)
      if (metadata.schemaVersion !== observation.normalizationSchemaVersion) {
        fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `${owner} ${entry.id} metadata uses the wrong normalization schema`)
      }
      if (sha256(artifact.lock) !== expected.lockSha256 || sha256(artifact.metadata) !== expected.metadataSha256) {
        fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `${owner} ${entry.id} artifact digest does not match`)
      }
    }
    return artifacts
  }
  if (observation.resolutionInputs.length !== policy.dependencyResolution.cases.length) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate has the wrong number of resolution inputs')
  for (const entry of policy.dependencyResolution.cases) {
    const expectedInput = observation.resolutionInputs.find((item) => item.id === entry.id)
    const currentInputSha256 = snapshot == null ? resolutionInputDigest(entry) : snapshot.inputDigests.get(entry.id)
    if (expectedInput == null || expectedInput.sha256 !== currentInputSha256) fail('FCR200_ADMISSION_STALE_BASE', `${entry.id} resolution input changed after observation`)
  }
  const fallbackArtifacts = verifyArtifactSet('fallback', observation.fallback, 'candidate fallback')
  const fallbackDigest = artifactSetDigest(policy, fallbackArtifacts)
  if (!observation.passDigests.fallback.every((digest) => digest === fallbackDigest)) {
    fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate fallback pass digests do not match its artifact set')
  }
  if (observation.upperEdge == null) {
    if (observation.passDigests.upperEdge.length !== 0) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate has upper-edge pass digests without upper-edge artifacts')
  } else {
    const upperArtifacts = verifyArtifactSet('upper-edge', observation.upperEdge, 'candidate upper edge')
    const upperDigest = artifactSetDigest(policy, upperArtifacts)
    if (!observation.passDigests.upperEdge.every((digest) => digest === upperDigest)) {
      fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate upper-edge pass digests do not match its artifact set')
    }
  }
  return fallbackArtifacts
}

function writeBaselineAtomically(policy, artifacts, toolchain, options = {}) {
  const root = baselineDirectory(policy)
  const paths = publicationPaths(root)
  const lock = acquirePublicationLock(root)
  try {
    recoverBaselinePublication(root)
    const currentManifest = fs.readFileSync(path.join(root, 'manifest.json'))
    if (options.expectedManifestSha256 != null && sha256(currentManifest) !== options.expectedManifestSha256) {
      fail('FCR200_ADMISSION_STALE_BASE', 'reviewed graph changed before publication')
    }
    fs.rmSync(paths.staged, { recursive: true, force: true })
    fs.mkdirSync(paths.staged)
    fs.writeFileSync(path.join(paths.staged, 'README.md'), fs.readFileSync(path.join(root, 'README.md')))
    writeArtifactTree(policy, artifacts, paths.staged)
    fs.writeFileSync(path.join(paths.staged, 'manifest.json'), jsonBytes(buildBaselineManifest(
      policy,
      artifacts,
      toolchain,
      {
        policySha256: options.policySha256,
        resolutionInputDigests: options.resolutionInputDigests
      }
    )))
    fs.writeFileSync(paths.journal, jsonBytes({ schemaVersion: 1 }))
    if (options.stopAfterPhase === 'prepared') throw diagnostic('FCR299_TEST_PUBLICATION_INTERRUPTION', 'stopped after prepared')
    fs.renameSync(root, paths.previous)
    if (options.stopAfterPhase === 'old-moved') throw diagnostic('FCR299_TEST_PUBLICATION_INTERRUPTION', 'stopped after old-moved')
    fs.renameSync(paths.staged, root)
    if (options.stopAfterPhase === 'new-installed') throw diagnostic('FCR299_TEST_PUBLICATION_INTERRUPTION', 'stopped after new-installed')
    fs.rmSync(paths.previous, { recursive: true, force: true })
    fs.rmSync(paths.journal, { force: true })
  } finally {
    releasePublicationLock(lock)
  }
}

function runAdmit(policy, args) {
  const candidateSourceDir = safeOutputDirectory(argumentValue(args, '--candidate-dir'), 'observation')
  const reviewedCandidateDigest = argumentValue(args, '--candidate-sha256')
  if (reviewedCandidateDigest == null) fail('FCR900_USAGE', 'admission requires --candidate-sha256 from the reviewed candidate tree')
  assertDigest(reviewedCandidateDigest, '--candidate-sha256')
  const candidateSnapshot = captureCandidateSnapshot(candidateSourceDir, reviewedCandidateDigest)
  let snapshot = null
  try {
    snapshot = captureAuthoritySnapshot(policy)
    verifyFixtureManifests(policy, snapshot)
    const candidateDir = candidateSnapshot.candidateDir
    const baseline = checkBaseline(policy, { allowCurrentAuthorityChange: true })
    const observation = readJson(path.join(candidateDir, 'observation.json'), 'candidate observation', 'FCR201_ADMISSION_ARTIFACT_INTEGRITY')
    const classification = readJson(path.join(candidateDir, 'classification.json'), 'candidate classification', 'FCR201_ADMISSION_ARTIFACT_INTEGRITY')
    assertCandidateFileInventory(policy, candidateDir, observation)
    if (observation.baseManifestSha256 !== baseline.manifestSha256) fail('FCR200_ADMISSION_STALE_BASE', 'reviewed graph changed after observation')
    const candidate = verifyObservationIntegrity(policy, candidateDir, observation, classification, snapshot)
    const baselineClassification = classifyArtifacts(policy, baseline.artifacts, candidate, {
      baselinePolicy: baseline.policy,
      baselineManifest: baseline.manifest,
      currentPolicySha256: sha256(snapshot.policyBytes),
      currentInputDigests: snapshot.inputDigests
    })
    if (!jsonBytes(baselineClassification).equals(jsonBytes(classification))) {
      fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', 'candidate classification does not describe its artifact bytes')
    }
    if (!classification.admissible) {
      const checksum = classification.changes.find((change) => change.category === 'package-checksum-changed')
      if (checksum != null) fail('FCR203_PACKAGE_IDENTITY_CHECKSUM_CHANGED', `${checksum.caseId} ${checksum.subject} changed checksum without changing package identity`)
      fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', 'candidate classification is not admissible')
    }
    const toolchain = loadSelectedToolchain()
    verifyLane(policy, 'minimum', toolchain)
    if (observation.actualRustc !== toolchain.rustcVersion || observation.actualCargo !== toolchain.cargoVersion) fail('FCR010_TOOLCHAIN_PAIR_MISMATCH', 'admission toolchain differs from observation toolchain')
    const verificationDir = safeOutputDirectory(null, 'admission-verification')
    const verified = runLockedCases(policy, candidate, candidate, toolchain, snapshot)
    runMutationProbe(policy, toolchain)
    const recomputed = classifyArtifacts(policy, baseline.artifacts, verified, {
      baselinePolicy: baseline.policy,
      baselineManifest: baseline.manifest,
      currentPolicySha256: sha256(snapshot.policyBytes),
      currentInputDigests: snapshot.inputDigests
    })
    if (!jsonBytes(recomputed).equals(jsonBytes(classification))) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', 'candidate classification changed during frozen admission verification')
    assertAuthoritySnapshotCurrent(policy, snapshot)
    writeReviewedEvidence(policy, verified, toolchain, verificationDir, {
      mode: 'admission-verification',
      lane: 'minimum',
      mutationRejected: true,
      admissible: classification.admissible
    })
    if (args.includes('--dry-run')) {
      console.log(`[fresh-cargo-resolution] candidate is admissible without re-resolution: ${path.relative(repoRoot, candidateSourceDir)}`)
      return
    }
    writeBaselineAtomically(policy, verified, toolchain, {
      expectedManifestSha256: baseline.manifestSha256,
      policySha256: sha256(snapshot.policyBytes),
      resolutionInputDigests: snapshot.inputDigests
    })
  } finally {
    if (snapshot != null) fs.rmSync(snapshot.root, { recursive: true, force: true })
    fs.rmSync(candidateSnapshot.root, { recursive: true, force: true })
  }
  console.log(`[fresh-cargo-resolution] admitted exact candidate from ${path.relative(repoRoot, candidateSourceDir)}`)
}

function main() {
  if (!Number.isInteger(commandTimeoutMs) || commandTimeoutMs < 1000) fail('FCR900_USAGE', 'FRESH_CARGO_COMMAND_TIMEOUT_MS must be at least 1000')
  const args = process.argv.slice(2)
  if (args.includes('--refresh-baseline')) fail('FCR900_USAGE_REMOVED_REFRESH', 'use observe-live followed by admit')
  const policy = loadPolicy()
  const mode = argumentValue(args, '--mode')
  const valueOptions = new Set(['--mode'])
  const flags = new Set()
  if (mode === 'verify-reviewed') {
    valueOptions.add('--lane')
    valueOptions.add('--out-dir')
  } else if (mode === 'observe-live') {
    valueOptions.add('--lane')
    valueOptions.add('--out-dir')
    flags.add('--include-upper-edge')
  } else if (mode === 'admit') {
    valueOptions.add('--candidate-dir')
    valueOptions.add('--candidate-sha256')
    flags.add('--dry-run')
  }
  const seen = new Set()
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index]
    if (seen.has(argument)) fail('FCR900_USAGE', `${argument} must appear at most once`)
    seen.add(argument)
    if (flags.has(argument)) continue
    if (!valueOptions.has(argument)) fail('FCR900_USAGE', `unknown argument for ${mode || '<missing-mode>'}: ${argument}`)
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) fail('FCR900_USAGE', `${argument} requires a value`)
    index += 1
  }
  if (mode === 'contract-only') {
    verifyFixtureManifests(policy)
    checkBaseline(policy)
    console.log('[fresh-cargo-resolution] reviewed graph contract OK')
    return
  }
  if (mode === 'mutation-only') {
    runMutationProbe(policy)
    return
  }
  if (mode === 'verify-reviewed') return runVerifyReviewed(policy, args)
  if (mode === 'observe-live') return runObserveLive(policy, args)
  if (mode === 'admit') return runAdmit(policy, args)
  fail('FCR900_USAGE', '--mode must be contract-only, mutation-only, verify-reviewed, observe-live, or admit')
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[fresh-cargo-resolution] ${error.message}`)
    process.exit(1)
  }
}

module.exports = {
  assertNoAncestorCargoConfiguration,
  assertControlledEnvironment,
  assertCandidateFileInventory,
  buildBaselineManifest,
  captureCandidateSnapshot,
  candidateTreeDigest,
  checkBaseline,
  classifyArtifacts,
  compareRustVersions,
  controlledCargoEnvironment,
  cargoEnvironment,
  loadSelectedToolchain,
  normalizationSchemaVersion,
  normalizeMetadata,
  ownedOutputDirectory,
  publicationPaths,
  recoverBaselinePublication,
  resolutionInputDigest,
  safeOutputDirectory,
  selectToolchainCommands,
  verifyObservationIntegrity,
  writeBaselineAtomically
}
