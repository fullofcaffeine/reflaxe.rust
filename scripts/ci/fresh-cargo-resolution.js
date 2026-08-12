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
const normalizationSchemaVersion = 1
const baselineSchemaVersion = 2
const observationSchemaVersion = 1
const { validateManifest } = require('./rust-toolchain-policy.js')

function diagnostic(id, message) {
  return new Error(`${id}: ${message}`)
}

function fail(id, message) {
  throw diagnostic(id, message)
}

function readJson(filePath, label, id = 'FCR020_BASELINE_INTEGRITY') {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    fail(id, `cannot read ${label}: ${error.message}`)
  }
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function jsonBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`)
}

function argumentValue(args, name, fallback = null) {
  const index = args.indexOf(name)
  if (index < 0) return fallback
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

function verifyFixtureManifests(policy) {
  for (const entry of policy.dependencyResolution.cases) {
    const source = fs.readFileSync(path.join(repoRoot, entry.fixture, 'Cargo.toml'), 'utf8')
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
    ...commands,
    rustcVersion: canonicalVersion(toolVersion(commands.rustc, 'rustc')),
    cargoVersion: canonicalVersion(toolVersion(commands.cargo, 'cargo')),
    sysroot
  }
}

const prohibitedEnvironmentExact = new Set([
  'CARGO_NET_OFFLINE', 'CARGO_BUILD_TARGET', 'CARGO_ENCODED_RUSTFLAGS', 'CARGO_INCREMENTAL',
  'RUSTC_BOOTSTRAP', 'RUSTFLAGS', 'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER', 'RUSTDOCFLAGS'
])

function environmentAffectsResolutionOrBuild(name) {
  return prohibitedEnvironmentExact.has(name)
    || /^CARGO_(BUILD|PROFILE|REGISTRIES|REGISTRY|SOURCE|TARGET)_/.test(name)
}

function assertControlledEnvironment(environment = process.env) {
  const bad = Object.keys(environment).filter(environmentAffectsResolutionOrBuild)
  if (bad.length > 0) fail('FCR011_UNCONTROLLED_ENVIRONMENT', `unset resolution-affecting environment variable(s): ${bad.sort().join(', ')}`)
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
    features: [...dependency.features].sort(),
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
      .sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)))
  }
}

function normalizeMetadata(raw, entry, policy, options = {}) {
  const packageKeyById = new Map(raw.packages.map((pkg) => [pkg.id, stablePackageKey(pkg)]))
  const featuresById = new Map((raw.resolve && raw.resolve.nodes || []).map((node) => [node.id, [...node.features].sort()]))
  const rootPackage = raw.resolve && raw.resolve.root != null ? packageKeyById.get(raw.resolve.root) : null
  if (rootPackage == null) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `${entry.id} Cargo metadata has no stable root package`)
  const packages = raw.packages.map((pkg) => ({
    id: stablePackageKey(pkg), name: pkg.name, version: pkg.version, source: pkg.source || 'path',
    rustVersion: pkg.rust_version == null ? null : canonicalVersion(pkg.rust_version),
    enabledFeatures: featuresById.get(pkg.id) || [],
    dependencies: pkg.dependencies.map(normalizeDependency).sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)))
  })).sort((left, right) => left.id.localeCompare(right.id))
  const incompatible = packages.filter((pkg) => pkg.rustVersion != null && compareRustVersions(pkg.rustVersion, policy.minimumSupportedRust) > 0)
  if (!options.allowIncompatible && incompatible.length > 0) fail('FCR102_OBSERVATION_INCOMPATIBLE', `${entry.id} resolved dependencies declaring Rust newer than ${policy.minimumSupportedRust}: ${incompatible.map((pkg) => `${pkg.name}@${pkg.version}=${pkg.rustVersion}`).join(', ')}`)
  const resolveNodes = (raw.resolve.nodes || []).map((node) => {
    const id = packageKeyById.get(node.id)
    if (id == null) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `${entry.id} Cargo metadata resolve graph contains an unknown package`)
    const dependencies = Array.isArray(node.deps)
      ? node.deps.map((dependency) => normalizeResolvedDependency(dependency, packageKeyById))
      : (node.dependencies || []).map((dependencyId) => ({ name: null, package: packageKeyById.get(dependencyId), kinds: [] }))
    dependencies.sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)))
    return { id, enabledFeatures: [...node.features].sort(), dependencies }
  }).sort((left, right) => left.id.localeCompare(right.id))
  const normalizeIds = (values, owner) => (values || []).map((id) => {
    const stable = packageKeyById.get(id)
    if (stable == null) fail('FCR021_REVIEWED_GRAPH_MISMATCH', `${entry.id} Cargo metadata ${owner} contains an unknown package`)
    return stable
  }).sort()
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
  assertControlledEnvironment()
  const environment = { ...process.env }
  for (const name of prohibitedEnvironmentExact) delete environment[name]
  for (const name of Object.keys(environment)) if (environmentAffectsResolutionOrBuild(name)) delete environment[name]
  return {
    ...environment,
    CARGO_HOME: cargoHome,
    CARGO_TARGET_DIR: targetDir,
    CARGO_TERM_COLOR: 'never',
    CARGO_NET_RETRY: process.env.CARGO_NET_RETRY || '10',
    CARGO_HTTP_MULTIPLEXING: process.env.CARGO_HTTP_MULTIPLEXING || 'false',
    RUSTC: toolchain.rustc
  }
}

function resolutionInputFiles(fixtureRoot) {
  const out = []
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      if (entry.name === 'target' || entry.name === 'Cargo.lock') continue
      const full = path.join(directory, entry.name)
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile() && (entry.name === 'Cargo.toml' || /(^|[/\\])\.cargo[/\\]config(?:\.toml)?$/.test(full))) out.push(full)
    }
  }
  visit(fixtureRoot)
  return out.sort()
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

function baselineDirectory(policy) {
  return path.resolve(repoRoot, policy.dependencyResolution.evidenceBaseline)
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

function lockfileFormat(bytes) {
  const match = /^version = ([0-9]+)$/m.exec(bytes.toString('utf8'))
  if (match == null) fail('FCR020_BASELINE_INTEGRITY', 'Cargo.lock has no supported lockfile version')
  return Number.parseInt(match[1], 10)
}

function policyDigest() {
  return sha256(fs.readFileSync(policyPath))
}

function buildBaselineManifest(policy, artifacts, toolchainIdentity) {
  const formats = new Set([...artifacts.values()].map((artifact) => lockfileFormat(artifact.lock)))
  if (formats.size !== 1) fail('FCR020_BASELINE_INTEGRITY', 'reviewed Cargo locks use different format versions')
  return {
    schemaVersion: baselineSchemaVersion,
    authority: 'reviewed-lock',
    policySchemaVersion: policy.schemaVersion,
    policySha256: policyDigest(),
    normalizationSchemaVersion,
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
      resolutionInputSha256: resolutionInputDigest(entry),
      lockSha256: sha256(artifacts.get(entry.id).lock),
      metadataSha256: sha256(artifacts.get(entry.id).metadata)
    }))
  }
}

function checkBaseline(policy) {
  const root = baselineDirectory(policy)
  const manifestPath = path.join(root, 'manifest.json')
  if (!fs.existsSync(path.join(root, 'README.md')) || !fs.existsSync(manifestPath)) fail('FCR020_BASELINE_INTEGRITY', 'reviewed graph documentation or manifest is missing')
  const manifest = readJson(manifestPath, 'reviewed graph manifest')
  if (manifest.schemaVersion !== baselineSchemaVersion || manifest.authority !== 'reviewed-lock') fail('FCR020_BASELINE_INTEGRITY', 'reviewed graph manifest schema or authority is invalid')
  const artifacts = artifactsFromDirectory(policy, root)
  const expected = buildBaselineManifest(policy, artifacts, { rustcVersion: manifest.admittedRustcVersion, cargoVersion: manifest.admittedCargoVersion })
  if (!jsonBytes(expected).equals(fs.readFileSync(manifestPath))) fail('FCR020_BASELINE_INTEGRITY', 'reviewed graph manifest, inputs, or artifact digests are stale')
  return { root, manifest, artifacts, manifestSha256: sha256(fs.readFileSync(manifestPath)) }
}

function runLockedCases(policy, artifacts, expectedMetadata, toolchain) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-rust-reviewed-resolution-'))
  const verified = new Map()
  try {
    for (const entry of policy.dependencyResolution.cases) {
      console.log(`[fresh-cargo-resolution] verify reviewed: ${entry.id}`)
      const caseRoot = path.join(root, 'cases', entry.id)
      fs.cpSync(path.join(repoRoot, entry.fixture), caseRoot, { recursive: true })
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
      fs.cpSync(path.join(repoRoot, entry.fixture), caseRoot, { recursive: true })
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

function assertExactObject(value, allowedKeys, owner) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `${owner} must be an object`)
  }
  const unknown = Object.keys(value).filter((key) => !allowedKeys.includes(key))
  const missing = allowedKeys.filter((key) => !Object.hasOwn(value, key))
  if (unknown.length > 0) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `${owner} contains unknown field(s): ${unknown.sort().join(', ')}`)
  if (missing.length > 0) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', `${owner} lacks field(s): ${missing.sort().join(', ')}`)
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
}

function compareValues(changes, caseId, category, subject, field, left, right) {
  if (JSON.stringify(left) !== JSON.stringify(right)) changes.push({ caseId, category, subject, field, old: left, new: right })
}

function classifyCase(entry, before, after, policy) {
  const changes = []
  const beforeLock = parseLock(before.lock)
  const afterLock = parseLock(after.lock)
  compareValues(changes, entry.id, 'lock-format', entry.id, 'lockfileFormat', beforeLock.format, afterLock.format)
  const lockIds = new Set([...beforeLock.packages.keys(), ...afterLock.packages.keys()])
  const removed = []
  const added = []
  for (const id of [...lockIds].sort()) {
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
  const oldMeta = JSON.parse(before.metadata)
  const newMeta = JSON.parse(after.metadata)
  assertNormalizedMetadataShape(oldMeta, `${entry.id} reviewed metadata`)
  assertNormalizedMetadataShape(newMeta, `${entry.id} candidate metadata`)
  for (const field of ['schemaVersion', 'caseId', 'contract', 'fixture', 'minimumSupportedRust', 'resolverVersion', 'incompatibleRustVersions', 'rootPackage', 'workspaceMembers', 'workspaceDefaultMembers']) {
    compareValues(changes, entry.id, field.startsWith('workspace') || field === 'rootPackage' ? 'topology-changed' : 'authority-input-changed', entry.id, field, oldMeta[field], newMeta[field])
  }
  const oldPackages = new Map(oldMeta.packages.map((pkg) => [pkg.id, pkg]))
  const newPackages = new Map(newMeta.packages.map((pkg) => [pkg.id, pkg]))
  for (const id of [...new Set([...oldPackages.keys(), ...newPackages.keys()])].sort()) {
    const left = oldPackages.get(id)
    const right = newPackages.get(id)
    if (left == null) {
      changes.push({ caseId: entry.id, category: 'metadata-package-added', subject: id, field: 'id', old: null, new: id })
      continue
    }
    if (right == null) {
      changes.push({ caseId: entry.id, category: 'metadata-package-removed', subject: id, field: 'id', old: id, new: null })
      continue
    }
    for (const field of ['name', 'version', 'source']) {
      compareValues(changes, entry.id, 'metadata-package-identity-changed', id, field, left[field], right[field])
    }
    compareValues(changes, entry.id, 'declared-msrv-changed', id, 'rustVersion', left.rustVersion, right.rustVersion)
    compareValues(changes, entry.id, 'enabled-features-changed', id, 'enabledFeatures', left.enabledFeatures, right.enabledFeatures)
    compareValues(changes, entry.id, 'declared-dependencies-changed', id, 'dependencies', left.dependencies, right.dependencies)
  }
  const oldNodes = new Map(oldMeta.resolvedGraph.nodes.map((node) => [node.id, node]))
  const newNodes = new Map(newMeta.resolvedGraph.nodes.map((node) => [node.id, node]))
  compareValues(changes, entry.id, 'topology-changed', entry.id, 'resolvedGraph.root', oldMeta.resolvedGraph.root, newMeta.resolvedGraph.root)
  for (const id of [...new Set([...oldNodes.keys(), ...newNodes.keys()])].sort()) {
    const left = oldNodes.get(id)
    const right = newNodes.get(id)
    if (left == null) changes.push({ caseId: entry.id, category: 'topology-node-added', subject: id, field: 'node', old: null, new: id })
    else if (right == null) changes.push({ caseId: entry.id, category: 'topology-node-removed', subject: id, field: 'node', old: id, new: null })
    else {
      compareValues(changes, entry.id, 'enabled-features-changed', id, 'resolvedEnabledFeatures', left.enabledFeatures, right.enabledFeatures)
      compareValues(changes, entry.id, 'topology-edges-changed', id, 'dependencies', left.dependencies, right.dependencies)
    }
  }
  if (changes.length === 0 && (!before.lock.equals(after.lock) || !before.metadata.equals(after.metadata))) changes.push({ caseId: entry.id, category: 'serialization-changed', subject: entry.id, field: 'bytes', old: sha256(Buffer.concat([before.lock, before.metadata])), new: sha256(Buffer.concat([after.lock, after.metadata])) })
  return changes
}

function classifyArtifacts(policy, baselineArtifacts, candidateArtifacts) {
  const changes = policy.dependencyResolution.cases.flatMap((entry) => classifyCase(entry, baselineArtifacts.get(entry.id), candidateArtifacts.get(entry.id), policy))
    .sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)))
  const checksumIncident = changes.some((change) => change.category === 'package-checksum-changed')
  const authorityInputChange = changes.some((change) => change.category === 'authority-input-changed'
    || change.category === 'lock-format' || change.category === 'serialization-changed')
  return {
    schemaVersion: 1,
    relation: changes.length === 0 ? 'match' : 'drift',
    admissible: !checksumIncident && !authorityInputChange,
    changes
  }
}

function safeOutputDirectory(value, lane = 'minimum') {
  const evidenceRoot = path.join(repoRoot, '.cache', 'fresh-cargo-resolution')
  const resolved = path.resolve(repoRoot, value || path.join(evidenceRoot, lane))
  const relative = path.relative(evidenceRoot, resolved)
  if (relative.length === 0 || relative.startsWith('..') || path.isAbsolute(relative)) fail('FCR900_USAGE', 'evidence output directory must be below .cache/fresh-cargo-resolution')
  return resolved
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

function writeObservation(policy, baseline, fallback, upperEdge, classification, toolchain, outDir, passDigests) {
  fs.rmSync(outDir, { recursive: true, force: true })
  fs.mkdirSync(outDir, { recursive: true })
  writeArtifactTree(policy, fallback, path.join(outDir, 'fallback'))
  if (upperEdge != null) writeArtifactTree(policy, upperEdge, path.join(outDir, 'upper-edge'))
  fs.writeFileSync(path.join(outDir, 'classification.json'), jsonBytes(classification))
  const observation = {
    schemaVersion: observationSchemaVersion,
    mode: 'observe-live',
    baseManifestSha256: baseline.manifestSha256,
    policySha256: policyDigest(),
    normalizationSchemaVersion,
    actualRustc: toolchain.rustcVersion,
    actualCargo: toolchain.cargoVersion,
    resolutionInputs: policy.dependencyResolution.cases.map((entry) => ({ id: entry.id, sha256: resolutionInputDigest(entry) })),
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
    || change.category === 'authority-input-changed' || change.category === 'lock-format'
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
  const verified = runLockedCases(policy, baseline.artifacts, baseline.artifacts, toolchain)
  let mutationRejected = null
  if (lane === 'minimum') {
    runMutationProbe(policy, toolchain)
    mutationRejected = true
  }
  writeReviewedEvidence(policy, verified, toolchain, safeOutputDirectory(argumentValue(args, '--out-dir'), `reviewed/${lane}`), {
    mode: 'verify-reviewed',
    lane,
    mutationRejected,
    admissible: true
  })
  console.log(`[fresh-cargo-resolution] reviewed graph OK (lane=${lane}, rustc=${toolchain.rustcVersion}, cargo=${toolchain.cargoVersion})`)
}

function runObserveLive(policy, args) {
  const lane = argumentValue(args, '--lane')
  if (lane !== 'minimum') fail('FCR900_USAGE', 'live observation requires --lane minimum')
  const toolchain = loadSelectedToolchain()
  verifyLane(policy, lane, toolchain)
  const baseline = checkBaseline(policy)
  let fallback = null
  const fallbackPassDigests = []
  for (let index = 1; index <= policy.dependencyResolution.observationRepeatRuns; index += 1) {
    const candidate = runFreshPass(policy, index, toolchain)
    fallbackPassDigests.push(artifactSetDigest(policy, candidate))
    if (fallback == null) fallback = candidate
    else compareArtifactMaps(policy, fallback, candidate, 'FCR100_OBSERVATION_NONDETERMINISTIC')
  }
  let upperEdge = null
  const upperPassDigests = []
  if (args.includes('--include-upper-edge')) {
    for (let index = 1; index <= policy.dependencyResolution.observationRepeatRuns; index += 1) {
      const candidate = runFreshPass(policy, index, toolchain, { upperEdge: true })
      upperPassDigests.push(artifactSetDigest(policy, candidate))
      if (upperEdge == null) upperEdge = candidate
      else compareArtifactMaps(policy, upperEdge, candidate, 'FCR100_OBSERVATION_NONDETERMINISTIC')
    }
  }
  runMutationProbe(policy, toolchain)
  const classification = classifyArtifacts(policy, baseline.artifacts, fallback)
  const outDir = safeOutputDirectory(argumentValue(args, '--out-dir'), 'observation')
  writeObservation(policy, baseline, fallback, upperEdge, classification, toolchain, outDir, { fallback: fallbackPassDigests, upperEdge: upperPassDigests })
  if (classification.relation === 'drift') fail('FCR101_OBSERVATION_DRIFT', `${classification.changes.length} reviewed dependency difference(s); candidate written to ${path.relative(repoRoot, outDir)}`)
  console.log('[fresh-cargo-resolution] live observation matches the reviewed graph')
}

function verifyObservationIntegrity(policy, candidateDir, observation, classification) {
  assertObservationShape(policy, observation, classification)
  if (observation.schemaVersion !== observationSchemaVersion || observation.mode !== 'observe-live') fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate observation schema or mode is invalid')
  if (observation.policySha256 !== policyDigest()) fail('FCR200_ADMISSION_STALE_BASE', 'policy changed after observation')
  if (observation.classificationSha256 !== sha256(jsonBytes(classification))) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate classification digest does not match')
  function verifyArtifactSet(directory, digests, owner) {
    if (digests.length !== policy.dependencyResolution.cases.length) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `${owner} has the wrong number of cases`)
    const artifacts = artifactsFromDirectory(policy, path.join(candidateDir, directory), 'FCR201_ADMISSION_ARTIFACT_INTEGRITY')
    for (const entry of policy.dependencyResolution.cases) {
      const expected = digests.find((item) => item.id === entry.id)
      if (expected == null) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `${owner} lacks ${entry.id} digests`)
      const artifact = artifacts.get(entry.id)
      if (sha256(artifact.lock) !== expected.lockSha256 || sha256(artifact.metadata) !== expected.metadataSha256) {
        fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', `${owner} ${entry.id} artifact digest does not match`)
      }
    }
    return artifacts
  }
  if (observation.resolutionInputs.length !== policy.dependencyResolution.cases.length) fail('FCR201_ADMISSION_ARTIFACT_INTEGRITY', 'candidate has the wrong number of resolution inputs')
  for (const entry of policy.dependencyResolution.cases) {
    const expectedInput = observation.resolutionInputs.find((item) => item.id === entry.id)
    if (expectedInput == null || expectedInput.sha256 !== resolutionInputDigest(entry)) fail('FCR200_ADMISSION_STALE_BASE', `${entry.id} resolution input changed after observation`)
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

function writeBaselineAtomically(policy, artifacts, toolchain) {
  const root = baselineDirectory(policy)
  const parent = path.dirname(root)
  const temp = fs.mkdtempSync(path.join(parent, '.fresh-cargo-admit-'))
  const backup = `${root}.previous-${process.pid}`
  try {
    fs.writeFileSync(path.join(temp, 'README.md'), fs.readFileSync(path.join(root, 'README.md')))
    writeArtifactTree(policy, artifacts, temp)
    fs.writeFileSync(path.join(temp, 'manifest.json'), jsonBytes(buildBaselineManifest(policy, artifacts, toolchain)))
    fs.renameSync(root, backup)
    try {
      fs.renameSync(temp, root)
    } catch (error) {
      fs.renameSync(backup, root)
      throw error
    }
    fs.rmSync(backup, { recursive: true, force: true })
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

function runAdmit(policy, args) {
  const candidateDir = safeOutputDirectory(argumentValue(args, '--candidate-dir'), 'observation')
  const baseline = checkBaseline(policy)
  const observation = readJson(path.join(candidateDir, 'observation.json'), 'candidate observation', 'FCR201_ADMISSION_ARTIFACT_INTEGRITY')
  const classification = readJson(path.join(candidateDir, 'classification.json'), 'candidate classification', 'FCR201_ADMISSION_ARTIFACT_INTEGRITY')
  if (observation.baseManifestSha256 !== baseline.manifestSha256) fail('FCR200_ADMISSION_STALE_BASE', 'reviewed graph changed after observation')
  const candidate = verifyObservationIntegrity(policy, candidateDir, observation, classification)
  const baselineClassification = classifyArtifacts(policy, baseline.artifacts, candidate)
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
  const verificationDir = safeOutputDirectory(path.join(candidateDir, 'admission-verification'))
  const verified = runLockedCases(policy, candidate, candidate, toolchain)
  runMutationProbe(policy, toolchain)
  const recomputed = classifyArtifacts(policy, baseline.artifacts, verified)
  if (!jsonBytes(recomputed).equals(jsonBytes(classification))) fail('FCR202_ADMISSION_UNCLASSIFIED_CHANGE', 'candidate classification changed during frozen admission verification')
  writeReviewedEvidence(policy, verified, toolchain, verificationDir, {
    mode: 'admission-verification',
    lane: 'minimum',
    mutationRejected: true,
    admissible: classification.admissible
  })
  if (args.includes('--dry-run')) {
    console.log(`[fresh-cargo-resolution] candidate is admissible without re-resolution: ${path.relative(repoRoot, candidateDir)}`)
    return
  }
  writeBaselineAtomically(policy, verified, toolchain)
  console.log(`[fresh-cargo-resolution] admitted exact candidate from ${path.relative(repoRoot, candidateDir)}`)
}

function main() {
  if (!Number.isInteger(commandTimeoutMs) || commandTimeoutMs < 1000) fail('FCR900_USAGE', 'FRESH_CARGO_COMMAND_TIMEOUT_MS must be at least 1000')
  const args = process.argv.slice(2)
  if (args.includes('--refresh-baseline')) fail('FCR900_USAGE_REMOVED_REFRESH', 'use observe-live followed by admit')
  const policy = loadPolicy()
  verifyFixtureManifests(policy)
  const mode = argumentValue(args, '--mode')
  if (mode === 'contract-only') {
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
  assertControlledEnvironment,
  buildBaselineManifest,
  checkBaseline,
  classifyArtifacts,
  compareRustVersions,
  normalizeMetadata,
  safeOutputDirectory,
  selectToolchainCommands,
  verifyObservationIntegrity
}
