#!/usr/bin/env node

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const repoRoot = path.resolve(__dirname, '..', '..')
const syncScript = path.join(repoRoot, 'scripts', 'release', 'sync-versions.js')
const verifyScript = path.join(repoRoot, 'scripts', 'release', 'verify-release-state.js')
const { buildReleaseState } = require(syncScript)

const generatedPostureFiles = [
  { path: 'README.md', canonicalLink: 'docs/semver-release-posture.md' },
  { path: 'docs/index.md', canonicalLink: 'semver-release-posture.md' },
  { path: 'docs/install-via-lix.md', canonicalLink: 'semver-release-posture.md' },
  { path: 'docs/progress-tracker.md', canonicalLink: 'semver-release-posture.md' },
  { path: 'docs/release.md', canonicalLink: 'semver-release-posture.md' },
  { path: 'docs/semver-release-posture.md', canonicalLink: '#current-decision' },
  { path: 'docs/start-here.md', canonicalLink: 'semver-release-posture.md' },
  { path: 'docs/vision-vs-implementation.md', canonicalLink: 'semver-release-posture.md' }
]
const generatedStateFiles = [
  'package.json',
  'package-lock.json',
  'haxelib.json',
  'haxe_libraries/reflaxe.rust.hxml',
  ...generatedPostureFiles.map((entry) => entry.path)
]

function writeFile(root, relativePath, content) {
  const absolutePath = path.join(root, relativePath)
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true })
  fs.writeFileSync(absolutePath, content)
}

function writeJson(root, relativePath, value) {
  writeFile(root, relativePath, `${JSON.stringify(value, null, 2)}\n`)
}

function manifest(stableApproved = false) {
  return {
    schemaVersion: 1,
    canonicalDocument: 'docs/semver-release-posture.md',
    stableGraduation: {
      major: 1,
      approved: stableApproved,
      approvalBead: stableApproved ? 'fixture-approval' : null,
      approvalDate: stableApproved ? '2030-01-02' : null
    },
    releaseLines: {
      '0': {
        channel: 'pre-1.0',
        status: 'intentional `0.x` pre-1.0 posture',
        maturity: 'production-capable preview on validated lanes'
      },
      '1': {
        channel: 'stable',
        status: 'stable `1.x` release posture',
        maturity: 'stable on the documented contract',
        requiresGraduationApproval: true
      }
    },
    generatedPostureFiles
  }
}

function createFixture(options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'release-state.'))
  const version = options.version || '0.81.2'

  writeJson(root, 'release-manifest.json', manifest(Boolean(options.stableApproved)))
  writeJson(root, 'package.json', { name: 'reflaxe-rust', version })
  writeJson(root, 'package-lock.json', {
    name: 'reflaxe-rust',
    version,
    packages: { '': { name: 'reflaxe-rust', version } }
  })
  writeJson(root, 'haxelib.json', {
    name: 'reflaxe.rust',
    version,
    releasenote: `v${version}: See CHANGELOG.md`
  })
  writeFile(root, 'haxe_libraries/reflaxe.rust.hxml', `-D reflaxe.rust=${version}\n`)

  for (const entry of generatedPostureFiles) {
    writeFile(
      root,
      entry.path,
      `${entry.path === 'README.md' ? `[![Version](https://img.shields.io/badge/version-${version}-blue)](https://example.invalid/releases)\n\n` : ''}` +
      '<!-- GENERATED:release-posture:start -->\nold release state\n<!-- GENERATED:release-posture:end -->\n'
    )
  }

  writeFile(root, 'CHANGELOG.md', `## [${version}] - fixture\n`)
  writeFile(root, `dist/reflaxe.rust-${version}.zip`, 'fixture zip placeholder')
  return root
}

function run(script, args, root, extraEnv = {}) {
  return spawnSync(process.execPath, [script, ...args, '--root', root], {
    encoding: 'utf8',
    cwd: root,
    env: { ...process.env, ...extraEnv }
  })
}

function removeFixture(root) {
  fs.rmSync(root, { recursive: true, force: true })
}

function captureGeneratedState(root) {
  return new Map(
    generatedStateFiles.map((relativePath) => [
      relativePath,
      fs.readFileSync(path.join(root, relativePath))
    ])
  )
}

function withFixture(options, assertion) {
  const root = createFixture(options)
  try {
    assertion(root)
  } finally {
    removeFixture(root)
  }
}

{
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'))
  assert.strictEqual(
    packageJson.release,
    undefined,
    'release workflow must live in the manifest-aware release.config.js'
  )
  const releaseConfig = require(path.join(repoRoot, 'release.config.js'))
  const plugins = releaseConfig.plugins
  const pluginName = (entry) => Array.isArray(entry) ? entry[0] : entry
  const execEntries = plugins
    .map((entry, index) => ({ entry, index }))
    .filter(({ entry }) => pluginName(entry) === '@semantic-release/exec')
  const gitIndex = plugins.findIndex((entry) => pluginName(entry) === '@semantic-release/git')
  const githubIndex = plugins.findIndex((entry) => pluginName(entry) === '@semantic-release/github')

  assert.strictEqual(execEntries.length, 2, 'release flow needs generator and post-commit verifier phases')
  const generatorExec = execEntries.find(({ entry }) => entry[1].prepareCmd.includes('sync-versions.js'))
  const verifierExec = execEntries.find(({ entry }) => entry[1].prepareCmd.includes('--prepared'))
  assert(generatorExec, 'generator exec phase is missing')
  assert(verifierExec, 'post-commit verifier exec phase is missing')
  assert(generatorExec.index < gitIndex, 'generation must run before the release commit')
  assert(gitIndex < verifierExec.index, 'prepared verification must run after the release commit')
  assert(verifierExec.index < githubIndex, 'verification plugin must precede GitHub publication')

  const gitPlugin = plugins[gitIndex]
  const gitAssets = new Set(gitPlugin[1].assets)
  const currentState = buildReleaseState(repoRoot, packageJson.version)
  for (const relativePath of [
    ...currentState.updates.keys(),
    'release-manifest.json',
    'CHANGELOG.md'
  ]) {
    assert(gitAssets.has(relativePath), `${relativePath} must be included in the release commit`)
  }
}

withFixture({}, (root) => {
  const sync = run(syncScript, ['0.81.2'], root)
  assert.strictEqual(sync.status, 0, sync.stderr)
  assert.strictEqual(
    sync.stdout,
    '[release-state] synced 0.81.2 (pre-1.0)\n'
  )

  const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8')
  assert.match(readme, /intentional `0\.x` pre-1\.0 posture/)
  assert.match(readme, /production-capable preview on validated lanes/)

  const firstGeneratedState = captureGeneratedState(root)
  const repeatedSync = run(syncScript, ['0.81.2'], root)
  assert.strictEqual(repeatedSync.status, 0, repeatedSync.stderr)
  for (const [relativePath, expected] of firstGeneratedState) {
    assert.deepStrictEqual(
      fs.readFileSync(path.join(root, relativePath)),
      expected,
      `${relativePath} must be byte-for-byte deterministic across repeated generation`
    )
  }

  const check = run(syncScript, ['--check'], root)
  assert.strictEqual(check.status, 0, check.stderr)
  assert.strictEqual(check.stdout, '[release-state] OK: 0.81.2 (pre-1.0)\n')

  writeFile(
    root,
    'docs/index.md',
    '<!-- GENERATED:release-posture:start -->\nstale\n<!-- GENERATED:release-posture:end -->\n'
  )
  const first = run(syncScript, ['--check'], root)
  const second = run(syncScript, ['--check'], root)
  assert.strictEqual(first.status, 1)
  assert.strictEqual(first.stderr, second.stderr, 'drift diagnostics must be deterministic')
  assert.match(first.stderr, /docs\/index\.md: generated release state is stale/)
})

withFixture({ version: '0.81.2' }, (root) => {
  const result = run(syncScript, ['1.0.0'], root)
  assert.strictEqual(result.status, 1)
  assert.match(result.stderr, /stable 1\.x generation requires an approved graduation record/)
})

withFixture({ version: '0.81.2', stableApproved: true }, (root) => {
  const result = run(syncScript, ['1.0.0'], root)
  assert.strictEqual(result.status, 0, result.stderr)
  assert.strictEqual(result.stdout, '[release-state] synced 1.0.0 (stable)\n')
  const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8')
  assert.match(readme, /stable `1\.x` release posture/)
})

withFixture({}, (root) => {
  const manifestPath = path.join(root, 'release-manifest.json')
  const releaseManifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  releaseManifest.releaseLines['2'] = {
    channel: 'future-stable',
    status: 'future stable posture',
    maturity: 'future stable contract'
  }
  writeJson(root, 'release-manifest.json', releaseManifest)
  const result = run(syncScript, ['2.0.0'], root)
  assert.strictEqual(result.status, 1)
  assert.match(result.stderr, /releaseLines\.2 must require graduation approval/)
})

withFixture({}, (root) => {
  const sync = run(syncScript, ['0.81.2'], root)
  assert.strictEqual(sync.status, 0, sync.stderr)

  const fakeBin = path.join(root, 'fake-bin')
  fs.mkdirSync(fakeBin, { recursive: true })
  const commandFixture = path.join(repoRoot, 'test', 'fixtures', 'release-state-command.js')
  for (const command of ['git', 'gh', 'unzip']) {
    const commandPath = path.join(fakeBin, command)
    writeFile(root, `fake-bin/${command}`, `#!/usr/bin/env node\nrequire(${JSON.stringify(commandFixture)})\n`)
    fs.chmodSync(commandPath, 0o755)
  }

  const prepared = run(verifyScript, ['0.81.2', '--prepared'], root, {
    PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`,
    RELEASE_STATE_FIXTURE_VERSION: '0.81.2'
  })
  assert.strictEqual(prepared.status, 0, prepared.stderr)
  assert.strictEqual(prepared.stdout, '[release-state] verified prepared v0.81.2\n')

  const preparedDrift = run(verifyScript, ['0.81.2', '--prepared'], root, {
    PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`,
    RELEASE_STATE_FIXTURE_VERSION: '0.81.2',
    RELEASE_STATE_FIXTURE_TAG_DRIFT: '1'
  })
  assert.strictEqual(preparedDrift.status, 1)
  assert.match(
    preparedDrift.stderr,
    /docs\/index\.md: prepared release content does not match generated release state/
  )

  const verified = run(verifyScript, ['0.81.2', '--published'], root, {
    PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`,
    RELEASE_STATE_FIXTURE_VERSION: '0.81.2'
  })
  assert.strictEqual(verified.status, 0, verified.stderr)
  assert.strictEqual(verified.stdout, '[release-state] verified published v0.81.2\n')

  const missingAsset = run(verifyScript, ['0.81.2', '--published'], root, {
    PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`,
    RELEASE_STATE_FIXTURE_VERSION: '0.81.2',
    RELEASE_STATE_FIXTURE_MISSING_ASSET: '1'
  })
  assert.strictEqual(missingAsset.status, 1)
  assert.match(missingAsset.stderr, /published GitHub Release is missing reflaxe\.rust-0\.81\.2\.zip/)

  const wrongReleaseKind = run(verifyScript, ['0.81.2', '--published'], root, {
    PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`,
    RELEASE_STATE_FIXTURE_VERSION: '0.81.2',
    RELEASE_STATE_FIXTURE_PRERELEASE: '1'
  })
  assert.strictEqual(wrongReleaseKind.status, 1)
  assert.match(wrongReleaseKind.stderr, /GitHub Release prerelease flag does not match 0\.81\.2/)

  const taggedDrift = run(verifyScript, ['0.81.2', '--published'], root, {
    PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`,
    RELEASE_STATE_FIXTURE_VERSION: '0.81.2',
    RELEASE_STATE_FIXTURE_TAG_DRIFT: '1'
  })
  assert.strictEqual(taggedDrift.status, 1)
  assert.match(taggedDrift.stderr, /docs\/index\.md: tagged release content does not match generated release state/)

  const missingTag = run(verifyScript, ['0.81.2'], root, {
    PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`,
    RELEASE_STATE_FIXTURE_VERSION: '0.81.2',
    RELEASE_STATE_FIXTURE_MISSING_TAG: '1'
  })
  assert.strictEqual(missingTag.status, 1)
  assert.match(missingTag.stderr, /Git tag v0\.81\.2 is missing or does not resolve to a commit/)

  fs.unlinkSync(path.join(root, 'dist', 'reflaxe.rust-0.81.2.zip'))
  const missingArtifact = run(verifyScript, ['0.81.2'], root, {
    PATH: `${fakeBin}${path.delimiter}${process.env.PATH}`,
    RELEASE_STATE_FIXTURE_VERSION: '0.81.2'
  })
  assert.strictEqual(missingArtifact.status, 1)
  assert.match(missingArtifact.stderr, /release artifact dist\/reflaxe\.rust-0\.81\.2\.zip is missing/)
})

console.log('[release-state-test] OK')
