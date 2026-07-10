#!/usr/bin/env node

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const policyModulePath = path.join(repoRoot, 'scripts', 'release', 'release-policy.js')
const pluginModulePath = path.join(repoRoot, 'scripts', 'release', 'semantic-release-policy.cjs')

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`)
}

function approval(record) {
  return { record, date: '2026-07-10' }
}

function manifest(options = {}) {
  const lines = {
    0: { stage: 'initial-development', breakingBump: 'minor' },
    1: { stage: 'stable', approval: options.major1Approved ? approval('haxe_rust-major-1') : null }
  }
  if (options.includeMajor2) {
    lines[2] = { stage: 'stable', approval: options.major2Approved ? approval('haxe_rust-major-2') : null }
  }
  return { schemaVersion: 2, releaseLines: lines }
}

function logger() {
  return { log() {}, error() {}, success() {} }
}

async function analyze(plugin, root, lastVersion, messages) {
  return plugin.analyzeCommits(
    { policyPath: path.join(root, 'release-manifest.json') },
    {
      cwd: root,
      commits: messages.map((message, index) => ({ message, hash: String(index + 1).padStart(40, '0') })),
      lastRelease: { version: lastVersion },
      logger: logger()
    }
  )
}

async function verify(plugin, root, version) {
  return plugin.verifyRelease(
    { policyPath: path.join(root, 'release-manifest.json') },
    { cwd: root, nextRelease: { version }, logger: logger() }
  )
}

async function expectReject(promise, pattern) {
  await assert.rejects(promise, pattern)
}

async function main() {
  assert(fs.existsSync(policyModulePath), 'release policy module must exist')
  assert(fs.existsSync(pluginModulePath), 'semantic-release policy plugin must exist')

  const policyApi = require(policyModulePath)
  const plugin = require(pluginModulePath)
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-release-policy-'))

  try {
    writeJson(path.join(root, 'release-manifest.json'), manifest())

    assert.strictEqual(await analyze(plugin, root, '0.81.3', ['fix: repair output']), 'patch')
    assert.strictEqual(await analyze(plugin, root, '0.81.3', ['feat: add facade']), 'minor')
    assert.strictEqual(
      await analyze(plugin, root, '0.81.3', ['feat!: replace an unstable API']),
      'minor',
      'breaking changes on an ungraduated 0.x line must remain on the initial-development line'
    )

    await verify(plugin, root, '0.82.0')
    await expectReject(verify(plugin, root, '1.0.0'), /stable major 1 requires an approved release record/)

    writeJson(path.join(root, 'release-manifest.json'), manifest({ major1Approved: true }))
    assert.strictEqual(await analyze(plugin, root, '0.82.0', ['feat!: graduate the stable contract']), 'major')
    await verify(plugin, root, '1.0.0')

    writeJson(
      path.join(root, 'release-manifest.json'),
      manifest({ major1Approved: true, includeMajor2: true, major2Approved: false })
    )
    assert.strictEqual(await analyze(plugin, root, '1.4.2', ['feat!: replace the stable API']), 'major')
    await expectReject(verify(plugin, root, '2.0.0'), /stable major 2 requires an approved release record/)

    writeJson(
      path.join(root, 'release-manifest.json'),
      manifest({ major1Approved: true, includeMajor2: true, major2Approved: true })
    )
    await verify(plugin, root, '1.9.0')
    await verify(plugin, root, '2.0.0')

    await expectReject(verify(plugin, root, '3.0.0'), /no release policy for major 3/)
    await expectReject(verify(plugin, root, '1.0.0-rc.1'), /prerelease channels are not enabled/)
    await expectReject(verify(plugin, root, '1.0.0+build.7'), /build metadata is not enabled/)
    await expectReject(verify(plugin, root, '1.0.0-alpha..1'), /invalid semantic version/)
    await expectReject(verify(plugin, root, '1.0.0-01'), /invalid semantic version/)
    await expectReject(verify(plugin, root, '9007199254740993.0.0'), /invalid semantic version/)

    const malformed = manifest()
    malformed.releaseLines['0'] = { stage: 'stable', approval: approval('wrong-stage') }
    writeJson(path.join(root, 'release-manifest.json'), malformed)
    assert.throws(
      () => policyApi.loadReleasePolicy(path.join(root, 'release-manifest.json')),
      /major 0 must use stage initial-development/
    )

    const incomplete = manifest({ major1Approved: true })
    incomplete.releaseLines['1'].approval.date = '2026-02-30'
    writeJson(path.join(root, 'release-manifest.json'), incomplete)
    assert.throws(
      () => policyApi.loadReleasePolicy(path.join(root, 'release-manifest.json')),
      /releaseLines\.1\.approval\.date must be a real YYYY-MM-DD date/
    )

    const futureDated = manifest({ major1Approved: true })
    futureDated.releaseLines['1'].approval.date = '2999-01-01'
    writeJson(path.join(root, 'release-manifest.json'), futureDated)
    assert.throws(
      () => policyApi.loadReleasePolicy(path.join(root, 'release-manifest.json')),
      /releaseLines\.1\.approval\.date must not be future-dated/
    )

    const configSource = fs.readFileSync(path.join(repoRoot, 'release.config.js'), 'utf8')
    assert(!configSource.includes('sync-versions'), 'release configuration must not load generated version state')
    const releaseConfig = require(path.join(repoRoot, 'release.config.js'))
    const pluginNames = releaseConfig.plugins.map((entry) => (Array.isArray(entry) ? entry[0] : entry))
    assert(!pluginNames.includes('@semantic-release/git'), 'publication must not create a release commit')
    assert(!pluginNames.includes('@semantic-release/changelog'), 'publication must not mutate the changelog')

    assert.strictEqual(require(path.join(repoRoot, 'package.json')).version, '0.0.0-development')
    const lock = require(path.join(repoRoot, 'package-lock.json'))
    assert.strictEqual(lock.version, '0.0.0-development')
    assert.strictEqual(lock.packages[''].version, '0.0.0-development')
    assert.strictEqual(require(path.join(repoRoot, 'haxelib.json')).version, '0.0.0')
    assert.match(
      fs.readFileSync(path.join(repoRoot, 'haxe_libraries', 'reflaxe.rust.hxml'), 'utf8'),
      /-D reflaxe\.rust=0\.0\.0-development/
    )
    const readme = fs.readFileSync(path.join(repoRoot, 'README.md'), 'utf8')
    assert.match(readme, /img\.shields\.io\/github\/v\/release\/fullofcaffeine\/reflaxe\.rust/)
    assert(!readme.includes('GENERATED:release-posture'), 'README maturity policy must not be patch-version generated state')

    console.log('[release-policy-test] OK')
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

main().catch((error) => {
  console.error(error.stack || error.message)
  process.exit(1)
})
