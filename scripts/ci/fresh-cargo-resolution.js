#!/usr/bin/env node
/**
 * Why:
 * A generated crate's `rust-version` rejects an incompatible compiler, but it does not by itself
 * freeze future semver-compatible dependency selection. Resolver preferences, undeclared dependency
 * MSRVs, and an updated registry can otherwise move a fresh application graph above the supported
 * Rust floor without changing this repository.
 *
 * What:
 * Proves the policy-owned minimal, portable, systems/TLS, async-feature, and metal graphs from an
 * empty Cargo home per case. It records stable lockfiles and path-free normalized metadata, rejects
 * declared dependency MSRVs above the floor, checks/tests on the selected lane, and compares the
 * graph with a reviewed repository baseline.
 *
 * How:
 * Two independent passes remove fixture locks and resolve each case in isolated temporary homes.
 * Their lock/metadata bytes must agree. The first pass also runs locked check/test, and a synthetic
 * semver-compatible dependency with a newer Rust requirement must fail. Exact-minimum refreshes are
 * explicit; normal minimum/current CI can only compare with the reviewed baseline and write bounded
 * evidence under `.cache/fresh-cargo-resolution`.
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
const { validateManifest } = require('./rust-toolchain-policy.js')

function fail(message) {
  throw new Error(message)
}

function readJson(filePath, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    fail(`cannot read ${label}: ${error.message}`)
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
  if (index + 1 >= args.length) fail(`${name} requires a value`)
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
  if (leftParts == null || rightParts == null) fail(`cannot compare Rust versions ${left} and ${right}`)
  for (let index = 0; index < leftParts.length; index += 1) {
    if (leftParts[index] < rightParts[index]) return -1
    if (leftParts[index] > rightParts[index]) return 1
  }
  return 0
}

function canonicalVersion(value) {
  const parts = parseRustVersion(value)
  if (parts == null) fail(`invalid Rust version: ${value}`)
  return parts.map((part) => part.toString()).join('.')
}

function nextRustMinor(value) {
  const parts = parseRustVersion(value)
  if (parts == null) fail(`invalid Rust version: ${value}`)
  return `${parts[0]}.${parts[1] + 1n}.0`
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function sanitizeOutput(value, replacements) {
  let out = value || ''
  const ordered = replacements
    .filter(([from]) => typeof from === 'string' && from.length > 0)
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
  if (result.error != null && result.error.code === 'ETIMEDOUT') {
    fail(`${options.label || command} exceeded ${commandTimeoutMs}ms`)
  }
  if (result.error != null) {
    fail(`${options.label || command} could not start: ${sanitizeOutput(result.error.message, options.replacements || [])}`)
  }
  if (!options.allowFailure && result.status !== 0) {
    const output = sanitizeOutput(`${result.stdout || ''}\n${result.stderr || ''}`, options.replacements || [])
    fail(`${options.label || command} failed with status ${result.status}\n${output.trim()}`)
  }
  return result
}

function loadPolicy() {
  const policy = readJson(policyPath, 'Rust toolchain policy')
  const errors = validateManifest(policy)
  if (errors.length > 0) fail(`invalid Rust toolchain policy:\n- ${errors.join('\n- ')}`)
  return policy
}

function exactManifestField(source, field) {
  const escaped = field.replace('-', '\\-')
  const match = source.match(new RegExp(`^${escaped} = "([^"]+)"$`, 'm'))
  return match == null ? null : match[1]
}

function verifyFixtureManifests(policy) {
  for (const entry of policy.dependencyResolution.cases) {
    const manifestPath = path.join(repoRoot, entry.fixture, 'Cargo.toml')
    const source = fs.readFileSync(manifestPath, 'utf8')
    if (exactManifestField(source, 'rust-version') !== policy.minimumSupportedRust) {
      fail(`${entry.id} fixture rust-version does not match ${policy.minimumSupportedRust}`)
    }
    if (exactManifestField(source, 'resolver') !== policy.dependencyResolution.resolverVersion) {
      fail(`${entry.id} fixture resolver does not match ${policy.dependencyResolution.resolverVersion}`)
    }
  }
}

function toolVersion(command, label) {
  const result = runCommand(command, ['--version'], { label })
  const match = new RegExp(`^${label} ([^ ]+)`).exec(result.stdout.trim())
  if (match == null) fail(`cannot parse ${label} version from: ${result.stdout.trim()}`)
  return match[1]
}

/**
 * Why:
 * Rustup chooses a toolchain from the command's working directory. The repository can therefore
 * select its pinned compiler while an isolated Cargo fixture outside the repository silently uses
 * the user's rolling default toolchain.
 *
 * What:
 * Resolves Cargo and rustc to the concrete binaries in the sysroot selected while the process is
 * still rooted in this repository. Explicit CARGO_BIN/RUSTC_BIN overrides remain authoritative.
 *
 * How:
 * rustc reports its selected sysroot; the sibling binaries are then passed through every temporary
 * resolution workspace. Missing siblings fail closed so a probe can never report one compiler and
 * execute another.
 */
function selectToolchainCommands(options = {}) {
  const rustcCommand = options.rustcCommand || rustcBin
  const cargoCommand = options.cargoCommand || cargoBin
  const rustcExplicit = options.rustcExplicit == null ? process.env.RUSTC_BIN != null : options.rustcExplicit
  const cargoExplicit = options.cargoExplicit == null ? process.env.CARGO_BIN != null : options.cargoExplicit
  if (rustcExplicit && cargoExplicit) return { rustc: rustcCommand, cargo: cargoCommand }

  const readRustcSysroot = options.readRustcSysroot || (() => {
    const result = runCommand(rustcCommand, ['--print', 'sysroot'], { label: 'selected rustc sysroot' })
    return result.stdout.trim()
  })
  const pathExists = options.pathExists || fs.existsSync
  const platform = options.platform || process.platform
  const executableSuffix = platform === 'win32' ? '.exe' : ''
  const sysroot = readRustcSysroot()
  if (typeof sysroot !== 'string' || sysroot.trim().length === 0) fail('selected rustc returned an empty sysroot')

  const selectedRustc = path.join(sysroot, 'bin', `rustc${executableSuffix}`)
  const selectedCargo = path.join(sysroot, 'bin', `cargo${executableSuffix}`)
  if (!rustcExplicit && !pathExists(selectedRustc)) {
    fail(`selected Rust sysroot does not contain rustc at ${selectedRustc}`)
  }
  if (!cargoExplicit && !pathExists(selectedCargo)) {
    fail(`selected Rust sysroot does not contain cargo at ${selectedCargo}; set CARGO_BIN explicitly`)
  }
  return {
    rustc: rustcExplicit ? rustcCommand : selectedRustc,
    cargo: cargoExplicit ? cargoCommand : selectedCargo
  }
}

function loadSelectedToolchain() {
  const commands = selectToolchainCommands()
  return {
    ...commands,
    rustcVersion: canonicalVersion(toolVersion(commands.rustc, 'rustc')),
    cargoVersion: canonicalVersion(toolVersion(commands.cargo, 'cargo'))
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
    features: [...dependency.features].sort(),
    target: dependency.target || null
  }
}

function normalizeResolvedDependency(dependency, packageKeyById) {
  const packageId = packageKeyById.get(dependency.pkg)
  if (packageId == null) fail(`Cargo metadata resolve edge points to unknown package ${dependency.pkg}`)
  return {
    name: dependency.name,
    package: packageId,
    kinds: (dependency.dep_kinds || []).map((kind) => ({
      kind: kind.kind || 'normal',
      target: kind.target || null
    })).sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)))
  }
}

function normalizeMetadata(raw, entry, policy) {
  const packageKeyById = new Map(raw.packages.map((pkg) => [pkg.id, stablePackageKey(pkg)]))
  const featuresById = new Map((raw.resolve && raw.resolve.nodes || []).map((node) => [node.id, [...node.features].sort()]))
  const rootPackage = raw.resolve && raw.resolve.root != null ? packageKeyById.get(raw.resolve.root) : null
  if (rootPackage == null) fail(`${entry.id} Cargo metadata has no stable root package`)

  const packages = raw.packages.map((pkg) => ({
    id: stablePackageKey(pkg),
    name: pkg.name,
    version: pkg.version,
    source: pkg.source || 'path',
    rustVersion: pkg.rust_version == null ? null : canonicalVersion(pkg.rust_version),
    enabledFeatures: featuresById.get(pkg.id) || [],
    dependencies: pkg.dependencies.map(normalizeDependency)
      .sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)))
  })).sort((left, right) => left.id.localeCompare(right.id))

  const incompatible = packages.filter((pkg) => pkg.rustVersion != null
    && compareRustVersions(pkg.rustVersion, policy.minimumSupportedRust) > 0)
  if (incompatible.length > 0) {
    fail(`${entry.id} resolved dependencies declaring Rust newer than ${policy.minimumSupportedRust}: ${incompatible.map((pkg) => `${pkg.name}@${pkg.version}=${pkg.rustVersion}`).join(', ')}`)
  }

  const resolveNodes = (raw.resolve.nodes || []).map((node) => {
    const id = packageKeyById.get(node.id)
    if (id == null) fail(`${entry.id} Cargo metadata resolve graph contains an unknown package`)
    const dependencies = Array.isArray(node.deps)
      ? node.deps.map((dependency) => normalizeResolvedDependency(dependency, packageKeyById))
      : (node.dependencies || []).map((dependencyId) => {
          const packageId = packageKeyById.get(dependencyId)
          if (packageId == null) fail(`${entry.id} Cargo metadata resolve graph contains an unknown dependency`)
          return { name: null, package: packageId, kinds: [] }
        })
    dependencies.sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)))
    return {
      id,
      enabledFeatures: [...node.features].sort(),
      dependencies
    }
  }).sort((left, right) => left.id.localeCompare(right.id))

  function normalizePackageIds(values, owner) {
    return (values || []).map((id) => {
      const stable = packageKeyById.get(id)
      if (stable == null) fail(`${entry.id} Cargo metadata ${owner} contains an unknown package`)
      return stable
    }).sort()
  }

  return {
    schemaVersion: 1,
    caseId: entry.id,
    contract: entry.contract,
    fixture: entry.fixture,
    minimumSupportedRust: policy.minimumSupportedRust,
    resolverVersion: policy.dependencyResolution.resolverVersion,
    incompatibleRustVersions: policy.dependencyResolution.incompatibleRustVersions,
    rootPackage,
    workspaceMembers: normalizePackageIds(raw.workspace_members, 'workspace_members'),
    workspaceDefaultMembers: normalizePackageIds(raw.workspace_default_members, 'workspace_default_members'),
    resolvedGraph: {
      root: rootPackage,
      nodes: resolveNodes
    },
    packages
  }
}

function cargoEnvironment(cargoHome, targetDir, toolchain) {
  return {
    ...process.env,
    CARGO_HOME: cargoHome,
    CARGO_TARGET_DIR: targetDir,
    CARGO_TERM_COLOR: 'never',
    CARGO_NET_RETRY: process.env.CARGO_NET_RETRY || '10',
    CARGO_HTTP_MULTIPLEXING: process.env.CARGO_HTTP_MULTIPLEXING || 'false',
    RUSTC: toolchain.rustc
  }
}

function runResolutionPass(policy, passIndex, buildAndTest, toolchain) {
  const passRoot = fs.mkdtempSync(path.join(os.tmpdir(), `reflaxe-rust-fresh-resolution-${passIndex}-`))
  const artifacts = new Map()
  try {
    for (const entry of policy.dependencyResolution.cases) {
      console.log(`[fresh-cargo-resolution] pass ${passIndex}/${policy.dependencyResolution.repeatRuns}: ${entry.id}`)
      const caseRoot = path.join(passRoot, 'cases', entry.id)
      fs.cpSync(path.join(repoRoot, entry.fixture), caseRoot, { recursive: true })
      fs.rmSync(path.join(caseRoot, 'Cargo.lock'), { force: true })
      fs.rmSync(path.join(caseRoot, 'target'), { recursive: true, force: true })
      const cargoHome = path.join(passRoot, 'cargo-homes', entry.id)
      fs.mkdirSync(cargoHome, { recursive: true })
      if (fs.readdirSync(cargoHome).length !== 0) fail(`${entry.id} Cargo home was not empty before resolution`)
      const targetDir = path.join(passRoot, 'targets', entry.id)
      const env = cargoEnvironment(cargoHome, targetDir, toolchain)
      const replacements = [[passRoot, '<fresh-resolution>'], [repoRoot, '<repo>']]

      runCommand(toolchain.cargo, ['generate-lockfile', '--quiet'], {
        cwd: caseRoot,
        env,
        label: `${entry.id} lockfile generation`,
        replacements
      })
      const metadataResult = runCommand(toolchain.cargo, ['metadata', '--locked', '--format-version', '1'], {
        cwd: caseRoot,
        env,
        label: `${entry.id} Cargo metadata`,
        replacements
      })
      const metadata = normalizeMetadata(JSON.parse(metadataResult.stdout), entry, policy)
      if (buildAndTest) {
        runCommand(toolchain.cargo, ['check', '--locked', '--quiet'], {
          cwd: caseRoot,
          env,
          label: `${entry.id} cargo check --locked`,
          replacements
        })
        runCommand(toolchain.cargo, ['test', '--locked', '--quiet'], {
          cwd: caseRoot,
          env,
          label: `${entry.id} cargo test --locked`,
          replacements
        })
      }
      artifacts.set(entry.id, {
        lock: fs.readFileSync(path.join(caseRoot, 'Cargo.lock')),
        metadata: jsonBytes(metadata)
      })
    }
    return artifacts
  } finally {
    fs.rmSync(passRoot, { recursive: true, force: true })
  }
}

function comparePasses(policy, baseline, candidate, passIndex) {
  for (const entry of policy.dependencyResolution.cases) {
    for (const field of ['lock', 'metadata']) {
      if (!baseline.get(entry.id)[field].equals(candidate.get(entry.id)[field])) {
        fail(`${entry.id} ${field} evidence changed between fresh pass 1 and pass ${passIndex}`)
      }
    }
  }
}

function baselineDirectory(policy) {
  return path.resolve(repoRoot, policy.dependencyResolution.evidenceBaseline)
}

function buildBaselineManifest(policy, artifacts) {
  return {
    schemaVersion: 1,
    policySchemaVersion: policy.schemaVersion,
    minimumSupportedRust: policy.minimumSupportedRust,
    resolverVersion: policy.dependencyResolution.resolverVersion,
    incompatibleRustVersions: policy.dependencyResolution.incompatibleRustVersions,
    applicationLockfile: policy.dependencyResolution.applicationLockfile,
    ciMode: policy.dependencyResolution.ciMode,
    emptyCargoHomePerCase: true,
    repeatRuns: policy.dependencyResolution.repeatRuns,
    cases: policy.dependencyResolution.cases.map((entry) => ({
      id: entry.id,
      contract: entry.contract,
      fixture: entry.fixture,
      lockSha256: sha256(artifacts.get(entry.id).lock),
      metadataSha256: sha256(artifacts.get(entry.id).metadata)
    }))
  }
}

function artifactsFromBaseline(policy) {
  const root = baselineDirectory(policy)
  const artifacts = new Map()
  for (const entry of policy.dependencyResolution.cases) {
    const caseRoot = path.join(root, entry.id)
    if (!fs.existsSync(path.join(caseRoot, 'Cargo.lock')) || !fs.existsSync(path.join(caseRoot, 'metadata.json'))) {
      fail(`fresh-resolution baseline is missing ${entry.id} lock or metadata evidence`)
    }
    artifacts.set(entry.id, {
      lock: fs.readFileSync(path.join(caseRoot, 'Cargo.lock')),
      metadata: fs.readFileSync(path.join(caseRoot, 'metadata.json'))
    })
  }
  return artifacts
}

function checkBaseline(policy, resolvedArtifacts = null) {
  const root = baselineDirectory(policy)
  const manifestPath = path.join(root, 'manifest.json')
  if (!fs.existsSync(path.join(root, 'README.md'))) fail('fresh-resolution baseline documentation is missing')
  if (!fs.existsSync(manifestPath)) fail('fresh-resolution baseline manifest is missing')
  const baselineArtifacts = artifactsFromBaseline(policy)
  const expected = jsonBytes(buildBaselineManifest(policy, baselineArtifacts))
  const actual = fs.readFileSync(manifestPath)
  if (!expected.equals(actual)) fail('fresh-resolution baseline manifest or artifact digests are stale')
  if (resolvedArtifacts != null) {
    for (const entry of policy.dependencyResolution.cases) {
      for (const field of ['lock', 'metadata']) {
        if (!baselineArtifacts.get(entry.id)[field].equals(resolvedArtifacts.get(entry.id)[field])) {
          fail(`${entry.id} fresh ${field} evidence differs from the reviewed baseline`)
        }
      }
    }
  }
  return baselineArtifacts
}

function writeBaseline(policy, artifacts) {
  const root = baselineDirectory(policy)
  if (!root.startsWith(`${repoRoot}${path.sep}`)) fail('baseline directory escapes the repository')
  const readmePath = path.join(root, 'README.md')
  if (!fs.existsSync(readmePath)) fail('fresh-resolution baseline documentation is missing')
  const documentation = fs.readFileSync(readmePath)
  fs.rmSync(root, { recursive: true, force: true })
  fs.mkdirSync(root, { recursive: true })
  fs.writeFileSync(path.join(root, 'README.md'), documentation)
  for (const entry of policy.dependencyResolution.cases) {
    const caseRoot = path.join(root, entry.id)
    fs.mkdirSync(caseRoot, { recursive: true })
    fs.writeFileSync(path.join(caseRoot, 'Cargo.lock'), artifacts.get(entry.id).lock)
    fs.writeFileSync(path.join(caseRoot, 'metadata.json'), artifacts.get(entry.id).metadata)
  }
  fs.writeFileSync(path.join(root, 'manifest.json'), jsonBytes(buildBaselineManifest(policy, artifacts)))
}

function safeOutputDirectory(value, lane) {
  const evidenceRoot = path.join(repoRoot, '.cache', 'fresh-cargo-resolution')
  const resolved = path.resolve(repoRoot, value || path.join(evidenceRoot, lane))
  const relative = path.relative(evidenceRoot, resolved)
  if (relative.length === 0 || relative.startsWith('..') || path.isAbsolute(relative)) {
    fail('evidence output directory must be below .cache/fresh-cargo-resolution')
  }
  return resolved
}

function writeEvidence(policy, artifacts, lane, actualRustc, actualCargo, outDir) {
  fs.rmSync(outDir, { recursive: true, force: true })
  fs.mkdirSync(outDir, { recursive: true })
  const cases = []
  for (const entry of policy.dependencyResolution.cases) {
    const caseRoot = path.join(outDir, entry.id)
    fs.mkdirSync(caseRoot, { recursive: true })
    const artifact = artifacts.get(entry.id)
    fs.writeFileSync(path.join(caseRoot, 'Cargo.lock'), artifact.lock)
    fs.writeFileSync(path.join(caseRoot, 'metadata.json'), artifact.metadata)
    const metadata = JSON.parse(artifact.metadata.toString('utf8'))
    cases.push({
      id: entry.id,
      contract: entry.contract,
      fixture: entry.fixture,
      packageCount: metadata.packages.length,
      packagesWithoutDeclaredRustVersion: metadata.packages.filter((pkg) => pkg.rustVersion == null).length,
      lockSha256: sha256(artifact.lock),
      metadataSha256: sha256(artifact.metadata)
    })
  }
  const summary = {
    schemaVersion: 1,
    policySchemaVersion: policy.schemaVersion,
    lane,
    actualRustc,
    actualCargo,
    minimumSupportedRust: policy.minimumSupportedRust,
    resolverVersion: policy.dependencyResolution.resolverVersion,
    incompatibleRustVersions: policy.dependencyResolution.incompatibleRustVersions,
    applicationLockfile: policy.dependencyResolution.applicationLockfile,
    ciMode: policy.dependencyResolution.ciMode,
    emptyCargoHomePerCase: true,
    repeatRuns: policy.dependencyResolution.repeatRuns,
    baselineMatched: true,
    checks: {
      lockfileGenerated: true,
      lockedMetadata: true,
      lockedCheck: true,
      lockedTest: true,
      repeatByteForByte: true,
      incompatibleDependencyMutationRejected: true
    },
    cases
  }
  fs.writeFileSync(path.join(outDir, 'summary.json'), jsonBytes(summary))
}

function runMutationProbe(policy, selectedToolchain = null) {
  const toolchain = selectedToolchain || loadSelectedToolchain()
  const actualRustc = toolchain.rustcVersion
  if (compareRustVersions(actualRustc, policy.minimumSupportedRust) < 0) {
    fail(`mutation probe requires rustc ${policy.minimumSupportedRust} or newer; found ${actualRustc}`)
  }
  const unsupported = nextRustMinor(actualRustc)
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-rust-msrv-mutation-'))
  try {
    fs.mkdirSync(path.join(root, 'src'), { recursive: true })
    fs.mkdirSync(path.join(root, 'msrv-probe', 'src'), { recursive: true })
    fs.writeFileSync(path.join(root, 'Cargo.toml'), `[package]\nname = "msrv_mutation_root"\nversion = "0.1.0"\nedition = "2021"\nrust-version = "${policy.minimumSupportedRust}"\nresolver = "${policy.dependencyResolution.resolverVersion}"\n\n[dependencies]\nmsrv_probe = { version = "1", path = "msrv-probe" }\n`)
    fs.writeFileSync(path.join(root, 'src', 'main.rs'), 'fn main() { assert_eq!(msrv_probe::value(), 1); }\n')
    fs.writeFileSync(path.join(root, 'msrv-probe', 'Cargo.toml'), `[package]\nname = "msrv_probe"\nversion = "1.1.0"\nedition = "2021"\nrust-version = "${unsupported}"\n\n[lib]\npath = "src/lib.rs"\n`)
    fs.writeFileSync(path.join(root, 'msrv-probe', 'src', 'lib.rs'), 'pub fn value() -> i32 { 1 }\n')
    const cargoHome = path.join(root, 'cargo-home')
    const env = cargoEnvironment(cargoHome, path.join(root, 'target'), toolchain)
    const replacements = [[root, '<msrv-mutation>'], [repoRoot, '<repo>']]
    runCommand(toolchain.cargo, ['generate-lockfile', '--quiet'], {
      cwd: root,
      env,
      label: 'MSRV mutation lockfile generation',
      replacements
    })
    const result = runCommand(toolchain.cargo, ['check', '--locked', '--quiet'], {
      cwd: root,
      env,
      label: 'MSRV mutation cargo check',
      replacements,
      allowFailure: true
    })
    if (result.status === 0) fail(`Cargo accepted a semver-compatible dependency requiring unsupported rustc ${unsupported}`)
    const output = sanitizeOutput(`${result.stdout || ''}\n${result.stderr || ''}`, replacements)
    if (!output.includes('msrv_probe') || !output.includes(unsupported)) {
      fail(`MSRV mutation failed without naming msrv_probe and required rustc ${unsupported}\n${output.trim()}`)
    }
    console.log(`[fresh-cargo-resolution] incompatible dependency mutation rejected (required=${unsupported}, actual=${actualRustc})`)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

function runFull(policy, args) {
  const lane = argumentValue(args, '--lane')
  if (!['minimum', 'current'].includes(lane)) fail('--lane must be minimum or current')
  const refreshBaseline = args.includes('--refresh-baseline')
  const checkBaselineOnly = args.includes('--check-baseline')
  if (refreshBaseline === checkBaselineOnly) {
    fail('full resolution requires exactly one of --check-baseline or --refresh-baseline')
  }
  if (refreshBaseline && lane !== 'minimum') {
    fail('--refresh-baseline is allowed only on the exact minimum lane')
  }
  const toolchain = loadSelectedToolchain()
  const actualRustc = toolchain.rustcVersion
  const actualCargo = toolchain.cargoVersion
  if (lane === 'minimum' && actualRustc !== policy.minimumSupportedRust) {
    fail(`minimum lane resolved rustc ${actualRustc}; expected exact ${policy.minimumSupportedRust}`)
  }
  if (compareRustVersions(actualRustc, policy.minimumSupportedRust) < 0) {
    fail(`${lane} lane rustc ${actualRustc} is older than ${policy.minimumSupportedRust}`)
  }
  const outDir = safeOutputDirectory(argumentValue(args, '--out-dir'), lane)

  let resolved = null
  for (let passIndex = 1; passIndex <= policy.dependencyResolution.repeatRuns; passIndex += 1) {
    const candidate = runResolutionPass(policy, passIndex, passIndex === 1, toolchain)
    if (resolved == null) resolved = candidate
    else comparePasses(policy, resolved, candidate, passIndex)
  }
  runMutationProbe(policy, toolchain)

  if (refreshBaseline) {
    writeBaseline(policy, resolved)
  } else if (checkBaselineOnly) {
    checkBaseline(policy, resolved)
  }

  writeEvidence(policy, resolved, lane, actualRustc, actualCargo, outDir)
  console.log(`[fresh-cargo-resolution] OK (lane=${lane}, rustc=${actualRustc}, cases=${resolved.size}, repeat=${policy.dependencyResolution.repeatRuns})`)
}

function main() {
  if (!Number.isInteger(commandTimeoutMs) || commandTimeoutMs < 1000) fail('FRESH_CARGO_COMMAND_TIMEOUT_MS must be at least 1000')
  const args = process.argv.slice(2)
  const policy = loadPolicy()
  verifyFixtureManifests(policy)
  if (args.includes('--contract-only')) {
    checkBaseline(policy)
    console.log('[fresh-cargo-resolution] policy and tracked baseline OK')
    return
  }
  if (args.includes('--mutation-only')) {
    runMutationProbe(policy)
    return
  }
  runFull(policy, args)
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[fresh-cargo-resolution] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = {
  buildBaselineManifest,
  checkBaseline,
  compareRustVersions,
  normalizeMetadata,
  safeOutputDirectory,
  selectToolchainCommands
}
