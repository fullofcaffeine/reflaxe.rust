#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const checker = path.join(repoRoot, 'scripts', 'ci', 'rust-toolchain-policy.js')
const manifestPath = path.join(repoRoot, 'rust-toolchain-policy.json')

function run(args = [], env = process.env) {
  return cp.spawnSync(process.execPath, [checker, ...args], { cwd: repoRoot, encoding: 'utf8', env })
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`)
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
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-toolchain-policy-'))
  try {
    const supported = run(['--assert-supported', canonical.minimumSupportedRust])
    assert.strictEqual(supported.status, 0, supported.stderr || supported.stdout)
    expectFailure(run(['--assert-supported', '0.0.0']), /unsupported.*requires rustc.*or newer/is)
    expectFailure(run(['--assert-supported', '1.96.0-beta.1']), /canonical major\.minor\.patch/)

    const githubOutput = path.join(root, 'github-output')
    const githubEnv = path.join(root, 'github-env')
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
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }

  console.log('[rust-toolchain-policy-test] OK')
}

main()
