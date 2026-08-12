#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const checker = path.join(repoRoot, 'scripts', 'ci', 'rust-toolchain-policy.js')
const freshResolutionChecker = path.join(repoRoot, 'scripts', 'ci', 'fresh-cargo-resolution.js')
const manifestPath = path.join(repoRoot, 'rust-toolchain-policy.json')
const freshResolutionBaselinePath = path.join(repoRoot, 'test', 'compatibility-baselines', 'fresh-cargo-resolution', 'manifest.json')
const freshResolutionApi = require(freshResolutionChecker)

function run(args = [], env = process.env) {
  return cp.spawnSync(process.execPath, [checker, ...args], { cwd: repoRoot, encoding: 'utf8', env })
}

function runFreshResolution(args = [], env = process.env) {
  return cp.spawnSync(process.execPath, [freshResolutionChecker, ...args], { cwd: repoRoot, encoding: 'utf8', env })
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`)
}

function jsonBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`)
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function expectFailure(result, pattern) {
  assert.notStrictEqual(result.status, 0, 'toolchain policy guard unexpectedly succeeded')
  assert.match(`${result.stdout}\n${result.stderr}`, pattern)
}

function main() {
  assert(fs.existsSync(checker), 'Rust toolchain policy guard must exist')
  assert(fs.existsSync(manifestPath), 'Rust toolchain policy manifest must exist')

  const baseline = run(['--check'])
  assert.strictEqual(baseline.status, 0, baseline.stderr || baseline.stdout)

  const firstHaxe = run(['--render', 'haxe'])
  const secondHaxe = run(['--render', 'haxe'])
  assert.strictEqual(firstHaxe.status, 0, firstHaxe.stderr)
  assert.strictEqual(secondHaxe.status, 0, secondHaxe.stderr)
  assert.strictEqual(firstHaxe.stdout, secondHaxe.stdout, 'generated Haxe policy must be byte-for-byte repeatable')

  const firstToml = run(['--render', 'toml'])
  const secondToml = run(['--render', 'toml'])
  assert.strictEqual(firstToml.status, 0, firstToml.stderr)
  assert.strictEqual(secondToml.status, 0, secondToml.stderr)
  assert.strictEqual(firstToml.stdout, secondToml.stdout, 'generated rust-toolchain.toml must be byte-for-byte repeatable')

  const firstDocs = run(['--render', 'docs'])
  const secondDocs = run(['--render', 'docs'])
  assert.strictEqual(firstDocs.status, 0, firstDocs.stderr)
  assert.strictEqual(secondDocs.status, 0, secondDocs.stderr)
  assert.strictEqual(firstDocs.stdout, secondDocs.stdout, 'generated policy summary must be byte-for-byte repeatable')

  const canonical = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  assert.strictEqual(canonical.schemaVersion, 3, 'reviewed dependency authority requires Rust toolchain policy schema v3')
  assert.deepStrictEqual(canonical.dependencyResolution, {
    resolverVersion: '3',
    incompatibleRustVersions: 'fallback',
    applicationLockfile: 'commit',
    ciMode: 'locked',
    evidenceBaseline: 'test/compatibility-baselines/fresh-cargo-resolution',
    requiredGate: 'reviewed-lock',
    observationMode: 'fresh-live',
    observationRepeatRuns: 2,
    admissionToolchain: 'minimum-sysroot-pair',
    cases: [
      {
        id: 'minimal',
        contract: 'minimal generated crate',
        fixture: 'test/snapshot/hello_trace/intended'
      },
      {
        id: 'portable',
        contract: 'portable generated crate',
        fixture: 'test/snapshot/v1_smoke/intended'
      },
      {
        id: 'systems',
        contract: 'systems and TLS generated crate',
        fixture: 'test/snapshot/sys_ssl_sni/intended'
      },
      {
        id: 'async-feature',
        contract: 'experimental async Tokio generated crate',
        fixture: 'test/snapshot/rust_async_tasks/intended_tokio'
      },
      {
        id: 'metal',
        contract: 'metal generated crate',
        fixture: 'test/snapshot/metal_v1_smoke/intended_metal'
      }
    ]
  }, 'rust-toolchain-policy.json must own the complete fresh-resolution and lock contract')
  assert(fs.existsSync(freshResolutionChecker), 'fresh Cargo resolution checker must exist')
  assert(fs.existsSync(freshResolutionBaselinePath), 'fresh Cargo resolution baseline manifest must exist')

  assert.strictEqual(
    typeof freshResolutionApi.selectToolchainCommands,
    'function',
    'fresh-resolution probes must resolve one paired Cargo/rustc toolchain before entering temporary directories'
  )
  const selectedToolchain = freshResolutionApi.selectToolchainCommands({
    rustcCommand: 'rustc-proxy',
    cargoCommand: 'cargo-proxy',
    rustcExplicit: false,
    cargoExplicit: false,
    platform: 'linux',
    readRustcSysroot: () => '/toolchains/1.96.0',
    pathExists: (candidate) => candidate === '/toolchains/1.96.0/bin/rustc'
      || candidate === '/toolchains/1.96.0/bin/cargo'
  })
  assert.deepStrictEqual(selectedToolchain, {
    rustc: '/toolchains/1.96.0/bin/rustc',
    cargo: '/toolchains/1.96.0/bin/cargo'
  }, 'temporary Cargo workspaces must not let rustup switch away from the repository-selected toolchain')
  assert.deepStrictEqual(freshResolutionApi.selectToolchainCommands({
    rustcCommand: '/custom/rustc',
    cargoCommand: '/custom/cargo',
    rustcExplicit: true,
    cargoExplicit: true,
    platform: 'linux',
    readRustcSysroot: () => '/toolchains/ignored',
    pathExists: () => true
  }), {
    rustc: '/custom/rustc',
    cargo: '/custom/cargo'
  }, 'explicit tool command overrides must remain authoritative')

  assert.throws(
    () => freshResolutionApi.assertControlledEnvironment({ RUSTFLAGS: '-C target-cpu=native' }),
    /FCR011_UNCONTROLLED_ENVIRONMENT.*RUSTFLAGS/,
    'dependency evidence must reject build flags inherited from an ambient shell'
  )
  assert.doesNotThrow(
    () => freshResolutionApi.assertControlledEnvironment({ HTTPS_PROXY: 'http://proxy.invalid' }),
    'network transport settings do not change dependency identity and may remain available'
  )
  assert.doesNotThrow(
    () => freshResolutionApi.assertControlledEnvironment({ CARGO_HOME: '/ambient/cache' }),
    'the evidence runner replaces an ambient Cargo home with an isolated directory'
  )
  assert.throws(
    () => freshResolutionApi.assertControlledEnvironment({ CARGO_PROFILE_RELEASE_LTO: 'true' }),
    /FCR011_UNCONTROLLED_ENVIRONMENT.*CARGO_PROFILE_RELEASE_LTO/,
    'ambient Cargo profile settings must not change the checked build'
  )

  const freshContract = runFreshResolution(['--mode', 'contract-only'])
  assert.strictEqual(freshContract.status, 0, freshContract.stderr || freshContract.stdout)

  const baselineRoot = path.dirname(freshResolutionBaselinePath)
  const baselineArtifacts = new Map(canonical.dependencyResolution.cases.map((entry) => [entry.id, {
    lock: fs.readFileSync(path.join(baselineRoot, entry.id, 'Cargo.lock')),
    metadata: fs.readFileSync(path.join(baselineRoot, entry.id, 'metadata.json'))
  }]))
  const checksumCandidate = new Map([...baselineArtifacts].map(([id, artifact]) => [id, {
    lock: Buffer.from(artifact.lock),
    metadata: Buffer.from(artifact.metadata)
  }]))
  checksumCandidate.get('minimal').lock = Buffer.from(
    checksumCandidate.get('minimal').lock.toString('utf8').replace(
      /checksum = "([0-9a-f])([0-9a-f]{63})"/,
      (_match, first, rest) => `checksum = "${first === '0' ? '1' : '0'}${rest}"`
    )
  )
  const checksumClassification = freshResolutionApi.classifyArtifacts(canonical, baselineArtifacts, checksumCandidate)
  assert.strictEqual(checksumClassification.admissible, false, 'a checksum change for one package identity must fail closed')
  assert(checksumClassification.changes.some((change) => change.category === 'package-checksum-changed'))

  const unknownMetadataCandidate = new Map([...baselineArtifacts].map(([id, artifact]) => [id, {
    lock: Buffer.from(artifact.lock),
    metadata: Buffer.from(artifact.metadata)
  }]))
  const unknownMetadata = JSON.parse(unknownMetadataCandidate.get('minimal').metadata)
  unknownMetadata.unreviewedField = true
  unknownMetadataCandidate.get('minimal').metadata = Buffer.from(`${JSON.stringify(unknownMetadata, null, 2)}\n`)
  assert.throws(
    () => freshResolutionApi.classifyArtifacts(canonical, baselineArtifacts, unknownMetadataCandidate),
    /FCR202_ADMISSION_UNCLASSIFIED_CHANGE.*unknown field.*unreviewedField/,
    'a new normalized metadata field must receive an explicit classifier before admission'
  )

  const baselineManifestBytes = fs.readFileSync(freshResolutionBaselinePath)
  const baselineManifest = JSON.parse(baselineManifestBytes)
  const classification = { schemaVersion: 1, relation: 'match', admissible: true, changes: [] }
  const admissionFixtureRoot = fs.mkdtempSync(path.join(repoRoot, '.cache', 'fresh-cargo-admission-test-'))
  try {
    const fallbackRoot = path.join(admissionFixtureRoot, 'fallback')
    fs.mkdirSync(fallbackRoot, { recursive: true })
    const artifactBytes = []
    for (const entry of canonical.dependencyResolution.cases) {
      fs.cpSync(path.join(baselineRoot, entry.id), path.join(fallbackRoot, entry.id), { recursive: true })
      artifactBytes.push(baselineArtifacts.get(entry.id).lock, baselineArtifacts.get(entry.id).metadata)
    }
    const artifactDigest = sha256(Buffer.concat(artifactBytes))
    const observation = {
      schemaVersion: 1,
      mode: 'observe-live',
      baseManifestSha256: sha256(baselineManifestBytes),
      policySha256: sha256(fs.readFileSync(manifestPath)),
      normalizationSchemaVersion: 1,
      actualRustc: canonical.minimumSupportedRust,
      actualCargo: canonical.minimumSupportedRust,
      resolutionInputs: baselineManifest.cases.map((entry) => ({ id: entry.id, sha256: entry.resolutionInputSha256 })),
      passDigests: { fallback: [artifactDigest, artifactDigest], upperEdge: [] },
      fallback: baselineManifest.cases.map((entry) => ({
        id: entry.id,
        lockSha256: entry.lockSha256,
        metadataSha256: entry.metadataSha256
      })),
      upperEdge: null,
      classificationSha256: sha256(jsonBytes(classification)),
      baselineRelation: 'match',
      admissible: true,
      lockedMetadataPassed: true,
      lockedCheckPassed: true,
      lockedTestPassed: true,
      repeatabilityPassed: true,
      mutationRejected: true,
      upperEdgeOnly: false
    }
    assert.doesNotThrow(
      () => freshResolutionApi.verifyObservationIntegrity(canonical, admissionFixtureRoot, observation, classification),
      'a digest-bound exact baseline candidate must pass admission integrity checks'
    )
    const tamperedLock = path.join(fallbackRoot, 'minimal', 'Cargo.lock')
    fs.appendFileSync(tamperedLock, '\n')
    assert.throws(
      () => freshResolutionApi.verifyObservationIntegrity(canonical, admissionFixtureRoot, observation, classification),
      /FCR201_ADMISSION_ARTIFACT_INTEGRITY.*artifact digest does not match/,
      'admission must reject a changed candidate artifact before Cargo runs'
    )
    fs.writeFileSync(tamperedLock, baselineArtifacts.get('minimal').lock)
    const staleObservation = structuredClone(observation)
    staleObservation.resolutionInputs[0].sha256 = '0'.repeat(64)
    assert.throws(
      () => freshResolutionApi.verifyObservationIntegrity(canonical, admissionFixtureRoot, staleObservation, classification),
      /FCR200_ADMISSION_STALE_BASE.*resolution input changed/,
      'admission must reject a candidate after its Cargo input changes'
    )
  } finally {
    fs.rmSync(admissionFixtureRoot, { recursive: true, force: true })
  }

  const incompatibleMutation = runFreshResolution(['--mode', 'mutation-only'])
  assert.strictEqual(incompatibleMutation.status, 0, incompatibleMutation.stderr || incompatibleMutation.stdout)
  expectFailure(
    runFreshResolution(['--lane', 'minimum', '--refresh-baseline']),
    /FCR900_USAGE_REMOVED_REFRESH.*observe-live followed by admit/
  )
  expectFailure(runFreshResolution(['--mode', 'unknown']), /mode must be/)

  assert.throws(
    () => freshResolutionApi.safeOutputDirectory(repoRoot, 'minimum'),
    /must be below \.cache\/fresh-cargo-resolution/,
    'fresh-resolution evidence output must not be able to delete arbitrary paths'
  )

  const [floorMajor, floorMinor] = canonical.minimumSupportedRust.split('.').map((part) => BigInt(part))
  const incompatibleRustVersion = `${floorMajor}.${floorMinor + 1n}.0`
  const incompatibleMetadata = {
    packages: [
      {
        id: 'path+file:///generated#app@0.1.0',
        name: 'app',
        version: '0.1.0',
        source: null,
        rust_version: canonical.minimumSupportedRust,
        dependencies: []
      },
      {
        id: 'registry+https://github.com/rust-lang/crates.io-index#future_dep@1.0.0',
        name: 'future_dep',
        version: '1.0.0',
        source: 'registry+https://github.com/rust-lang/crates.io-index',
        rust_version: incompatibleRustVersion,
        dependencies: []
      }
    ],
    resolve: {
      root: 'path+file:///generated#app@0.1.0',
      nodes: [
        { id: 'path+file:///generated#app@0.1.0', features: [] },
        { id: 'registry+https://github.com/rust-lang/crates.io-index#future_dep@1.0.0', features: [] }
      ]
    }
  }
  assert.throws(
    () => freshResolutionApi.normalizeMetadata(
      incompatibleMetadata,
      canonical.dependencyResolution.cases[0],
      canonical
    ),
    new RegExp(`resolved dependencies declaring Rust newer than ${canonical.minimumSupportedRust.replaceAll('.', '\\.')}.*future_dep@1\\.0\\.0=${incompatibleRustVersion.replaceAll('.', '\\.')}`),
    'normalized metadata must reject every dependency that declares an MSRV above the policy floor'
  )

  const cacheRoot = path.join(repoRoot, '.cache')
  fs.mkdirSync(cacheRoot, { recursive: true })
  const tamperedBaselineRoot = fs.mkdtempSync(path.join(cacheRoot, 'fresh-resolution-baseline-test-'))
  try {
    fs.cpSync(path.dirname(freshResolutionBaselinePath), tamperedBaselineRoot, { recursive: true })
    fs.appendFileSync(path.join(tamperedBaselineRoot, 'minimal', 'metadata.json'), ' ')
    const tamperedPolicy = structuredClone(canonical)
    tamperedPolicy.dependencyResolution.evidenceBaseline = path.relative(repoRoot, tamperedBaselineRoot)
    assert.throws(
      () => freshResolutionApi.checkBaseline(tamperedPolicy),
      /FCR020_BASELINE_INTEGRITY.*reviewed graph manifest, inputs, or artifact digests are stale/,
      'tracked dependency metadata must be integrity-protected by the baseline manifest'
    )
  } finally {
    fs.rmSync(tamperedBaselineRoot, { recursive: true, force: true })
  }

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-toolchain-policy-'))
  try {
    const supported = run(['--assert-supported', canonical.minimumSupportedRust])
    assert.strictEqual(supported.status, 0, supported.stderr || supported.stdout)
    const printedResolver = run(['--print', 'resolver'])
    assert.strictEqual(printedResolver.status, 0, printedResolver.stderr || printedResolver.stdout)
    assert.strictEqual(printedResolver.stdout, `${canonical.dependencyResolution.resolverVersion}\n`)
    expectFailure(run(['--assert-supported', '0.0.0']), /unsupported.*requires rustc.*or newer/is)
    expectFailure(run(['--assert-supported', '1.96.0-beta.1']), /canonical major\.minor\.patch/)

    const githubOutput = path.join(root, 'github-output')
    const githubEnv = path.join(root, 'github-env')
    const printedMinimum = run(['--print', 'minimum'], { ...process.env, GITHUB_OUTPUT: githubOutput })
    assert.strictEqual(printedMinimum.status, 0, printedMinimum.stderr || printedMinimum.stdout)
    assert.strictEqual(printedMinimum.stdout, `${canonical.minimumSupportedRust}\n`)
    const activation = run(
      ['--github-output', '--activate', 'minimum'],
      { ...process.env, GITHUB_OUTPUT: githubOutput, GITHUB_ENV: githubEnv }
    )
    assert.strictEqual(activation.status, 0, activation.stderr || activation.stdout)
    assert.match(fs.readFileSync(githubOutput, 'utf8'), new RegExp(`^minimum=${canonical.minimumSupportedRust}$`, 'm'))
    assert.strictEqual(fs.readFileSync(githubEnv, 'utf8'), `RUSTUP_TOOLCHAIN=${canonical.minimumSupportedRust}\n`)
    expectFailure(run(['--github-output', '--activate', 'unknown'], {
      ...process.env,
      GITHUB_OUTPUT: githubOutput,
      GITHUB_ENV: githubEnv
    }), /unknown activation lane/)

    const invalidMinimum = structuredClone(canonical)
    invalidMinimum.minimumSupportedRust = 'edition-2021'
    const invalidMinimumPath = path.join(root, 'invalid-minimum.json')
    writeJson(invalidMinimumPath, invalidMinimum)
    expectFailure(run(['--manifest', invalidMinimumPath, '--validate-only']), /minimumSupportedRust.*SemVer/)

    const legacySchema = structuredClone(canonical)
    legacySchema.schemaVersion = 2
    const legacySchemaPath = path.join(root, 'legacy-schema.json')
    writeJson(legacySchemaPath, legacySchema)
    expectFailure(run(['--manifest', legacySchemaPath, '--validate-only']), /schemaVersion must be 3/)

    const legacyFreshGate = structuredClone(canonical)
    legacyFreshGate.dependencyResolution.requiredGate = 'fresh-live'
    const legacyFreshGatePath = path.join(root, 'legacy-fresh-gate.json')
    writeJson(legacyFreshGatePath, legacyFreshGate)
    expectFailure(run(['--manifest', legacyFreshGatePath, '--validate-only']), /requiredGate must be reviewed-lock/)

    const missingAdmissionPair = structuredClone(canonical)
    missingAdmissionPair.dependencyResolution.admissionToolchain = 'minimum-rustc'
    const missingAdmissionPairPath = path.join(root, 'missing-admission-pair.json')
    writeJson(missingAdmissionPairPath, missingAdmissionPair)
    expectFailure(run(['--manifest', missingAdmissionPairPath, '--validate-only']), /admissionToolchain must be minimum-sysroot-pair/)

    const unknownPolicyField = structuredClone(canonical)
    unknownPolicyField.dependencyResolution.cases[0].fixtures = unknownPolicyField.dependencyResolution.cases[0].fixture
    const unknownPolicyFieldPath = path.join(root, 'unknown-policy-field.json')
    writeJson(unknownPolicyFieldPath, unknownPolicyField)
    expectFailure(run(['--manifest', unknownPolicyFieldPath, '--validate-only']), /case contains unknown field: fixtures/)

    const releaseBelowMinimum = structuredClone(canonical)
    releaseBelowMinimum.releaseToolchain = '1.95.0'
    const releaseBelowMinimumPath = path.join(root, 'release-below-minimum.json')
    writeJson(releaseBelowMinimumPath, releaseBelowMinimum)
    expectFailure(run(['--manifest', releaseBelowMinimumPath, '--validate-only']), /releaseToolchain.*minimumSupportedRust/)

    const patchFloorRaise = structuredClone(canonical)
    patchFloorRaise.floorRaiseRelease = 'patch'
    const patchFloorRaisePath = path.join(root, 'patch-floor-raise.json')
    writeJson(patchFloorRaisePath, patchFloorRaise)
    expectFailure(run(['--manifest', patchFloorRaisePath, '--validate-only']), /floorRaiseRelease must be minor/)

    const invalidCadence = structuredClone(canonical)
    invalidCadence.reviewCadenceWeeks = 0
    const invalidCadencePath = path.join(root, 'invalid-cadence.json')
    writeJson(invalidCadencePath, invalidCadence)
    expectFailure(run(['--manifest', invalidCadencePath, '--validate-only']), /reviewCadenceWeeks/)

    const legacyResolver = structuredClone(canonical)
    legacyResolver.dependencyResolution.resolverVersion = '2'
    const legacyResolverPath = path.join(root, 'legacy-resolver.json')
    writeJson(legacyResolverPath, legacyResolver)
    expectFailure(run(['--manifest', legacyResolverPath, '--validate-only']), /resolverVersion must be 3/)

    const unlockedCi = structuredClone(canonical)
    unlockedCi.dependencyResolution.ciMode = 'update'
    const unlockedCiPath = path.join(root, 'unlocked-ci.json')
    writeJson(unlockedCiPath, unlockedCi)
    expectFailure(run(['--manifest', unlockedCiPath, '--validate-only']), /ciMode must be locked/)

    const singleResolution = structuredClone(canonical)
    singleResolution.dependencyResolution.observationRepeatRuns = 1
    const singleResolutionPath = path.join(root, 'single-resolution.json')
    writeJson(singleResolutionPath, singleResolution)
    expectFailure(run(['--manifest', singleResolutionPath, '--validate-only']), /observationRepeatRuns must be at least 2/)

    const duplicateCase = structuredClone(canonical)
    duplicateCase.dependencyResolution.cases.push(structuredClone(duplicateCase.dependencyResolution.cases[0]))
    const duplicateCasePath = path.join(root, 'duplicate-case.json')
    writeJson(duplicateCasePath, duplicateCase)
    expectFailure(run(['--manifest', duplicateCasePath, '--validate-only']), /duplicate case id/)

    const escapingFixture = structuredClone(canonical)
    escapingFixture.dependencyResolution.cases[0].fixture = '../outside'
    const escapingFixturePath = path.join(root, 'escaping-fixture.json')
    writeJson(escapingFixturePath, escapingFixture)
    expectFailure(run(['--manifest', escapingFixturePath, '--validate-only']), /fixture must be repository-relative/)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }

  console.log('[rust-toolchain-policy-test] OK')
}

main()
