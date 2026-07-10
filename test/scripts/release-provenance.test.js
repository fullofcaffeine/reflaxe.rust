#!/usr/bin/env node

const assert = require('assert')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const provenanceModulePath = path.join(repoRoot, 'scripts', 'release', 'release-provenance.js')
const VERSION = '0.82.0'
const TAG = `v${VERSION}`
const SOURCE_SHA = '1234567890abcdef1234567890abcdef12345678'

function hash(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex')
}

function expectedRelease(zipPath, checksumPath, options = {}) {
  const zip = fs.readFileSync(zipPath)
  const checksum = fs.readFileSync(checksumPath)
  const assets = [
    {
      name: `reflaxe.rust-${VERSION}.zip`,
      size: zip.length,
      state: 'uploaded',
      digest: `sha256:${options.wrongDigest ? '0'.repeat(64) : hash(zip)}`
    },
    {
      name: `reflaxe.rust-${VERSION}.zip.sha256`,
      size: checksum.length,
      state: 'uploaded',
      digest: `sha256:${hash(checksum)}`
    }
  ]
  if (options.extraAsset) assets.push({ name: 'unexpected.zip', size: 1, state: 'uploaded', digest: `sha256:${'1'.repeat(64)}` })
  return {
    tagName: TAG,
    isDraft: false,
    isImmutable: options.mutable ? false : true,
    isPrerelease: false,
    assets
  }
}

function fakeRunner(release) {
  return (command, args) => {
    if (command === 'gh' && args[0] === 'release' && args[1] === 'view') return JSON.stringify(release)
    throw new Error(`unexpected command: ${command} ${args.join(' ')}`)
  }
}

function expectThrow(callback, pattern) {
  assert.throws(callback, pattern)
}

function main() {
  assert(fs.existsSync(provenanceModulePath), 'release provenance module must exist')
  const provenance = require(provenanceModulePath)
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-release-provenance-'))
  try {
    const zipPath = path.join(temp, 'reflaxe.rust.zip')
    const checksumPath = path.join(temp, 'reflaxe.rust.zip.sha256')
    fs.writeFileSync(zipPath, Buffer.from('deterministic fixture bytes'))
    fs.writeFileSync(checksumPath, `${hash(fs.readFileSync(zipPath))}  reflaxe.rust-${VERSION}.zip\n`)

    assert.deepStrictEqual(provenance.artifactNames(VERSION), {
      archive: `reflaxe.rust-${VERSION}.zip`,
      checksum: `reflaxe.rust-${VERSION}.zip.sha256`
    })

    provenance.verifyHostedRelease({
      version: VERSION,
      tag: TAG,
      zipPath,
      checksumPath,
      run: fakeRunner(expectedRelease(zipPath, checksumPath))
    })

    expectThrow(
      () =>
        provenance.verifyHostedRelease({
          version: VERSION,
          tag: TAG,
          zipPath,
          checksumPath,
          run: fakeRunner(expectedRelease(zipPath, checksumPath, { wrongDigest: true }))
        }),
      /hosted asset digest does not match the approved file/
    )
    expectThrow(
      () =>
        provenance.verifyHostedRelease({
          version: VERSION,
          tag: TAG,
          zipPath,
          checksumPath,
          run: fakeRunner(expectedRelease(zipPath, checksumPath, { extraAsset: true }))
        }),
      /hosted custom asset set does not match the release contract/
    )
    expectThrow(
      () =>
        provenance.verifyHostedRelease({
          version: VERSION,
          tag: TAG,
          zipPath,
          checksumPath,
          run: fakeRunner(expectedRelease(zipPath, checksumPath, { mutable: true }))
        }),
      /published GitHub Release is not immutable/
    )

    const identityRunner = (values) => (command, args) => {
      const key = `${command} ${args.join(' ')}`
      if (!Object.prototype.hasOwnProperty.call(values, key)) throw new Error(`unexpected command: ${key}`)
      return values[key]
    }
    const identityValues = {
      'git rev-parse HEAD^{commit}': `${SOURCE_SHA}\n`,
      [`git rev-parse refs/tags/${TAG}^{commit}`]: `${SOURCE_SHA}\n`,
      [`git ls-remote --tags origin refs/tags/${TAG} refs/tags/${TAG}^{}`]: `${SOURCE_SHA}\trefs/tags/${TAG}\n`
    }
    provenance.verifyTagIdentity({
      tag: TAG,
      sourceCommit: SOURCE_SHA,
      run: identityRunner(identityValues)
    })
    expectThrow(
      () =>
        provenance.verifyTagIdentity({
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          run: identityRunner({
            ...identityValues,
            [`git rev-parse refs/tags/${TAG}^{commit}`]: `${'a'.repeat(40)}\n`
          })
        }),
      /local release tag does not identify the CI-tested commit/
    )
    expectThrow(
      () =>
        provenance.verifyTagIdentity({
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          run: identityRunner({ ...identityValues, [`git ls-remote --tags origin refs/tags/${TAG} refs/tags/${TAG}^{}`]: '' })
        }),
      /remote release tag is missing/
    )

    const controls = {
      'gh api repos/fullofcaffeine/reflaxe.rust/immutable-releases': JSON.stringify({ enabled: true }),
      'gh api repos/fullofcaffeine/reflaxe.rust/rulesets': JSON.stringify([
        { id: 42, name: 'Immutable semantic version tags', target: 'tag', enforcement: 'active' }
      ]),
      'gh api repos/fullofcaffeine/reflaxe.rust/rulesets/42': JSON.stringify({
        id: 42,
        target: 'tag',
        enforcement: 'active',
        conditions: { ref_name: { include: ['refs/tags/v*'], exclude: [] } },
        rules: [{ type: 'deletion' }, { type: 'non_fast_forward' }]
      })
    }
    provenance.verifyHostReleaseControls({
      repository: 'fullofcaffeine/reflaxe.rust',
      run: identityRunner(controls)
    })
    expectThrow(
      () =>
        provenance.verifyHostReleaseControls({
          repository: 'fullofcaffeine/reflaxe.rust',
          run: identityRunner({
            ...controls,
            'gh api repos/fullofcaffeine/reflaxe.rust/immutable-releases': JSON.stringify({ enabled: false })
          })
        }),
      /immutable GitHub Releases are not enabled/
    )

    const config = require(path.join(repoRoot, 'release.config.js'))
    const names = config.plugins.map((entry) => (Array.isArray(entry) ? entry[0] : entry))
    assert.deepStrictEqual(names, [
      './scripts/release/semantic-release-policy.cjs',
      '@semantic-release/release-notes-generator',
      './scripts/release/haxelib-artifact-plugin.cjs',
      '@semantic-release/github',
      './scripts/release/published-verifier-plugin.cjs'
    ])

    console.log('[release-provenance-test] OK')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

main()
