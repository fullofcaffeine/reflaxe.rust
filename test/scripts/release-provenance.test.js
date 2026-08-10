#!/usr/bin/env node

const assert = require('assert')
const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')

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

    const receipt = provenance.createArtifactReceipt({
      version: VERSION,
      tag: TAG,
      sourceCommit: SOURCE_SHA,
      zipPath,
      checksumPath
    })
    provenance.verifyHostedRelease({
      receipt,
      run: fakeRunner(expectedRelease(zipPath, checksumPath))
    })
    const approvedRemote = expectedRelease(zipPath, checksumPath)
    fs.writeFileSync(zipPath, 'mutated after approval')
    fs.writeFileSync(checksumPath, 'mutated checksum after approval\n')
    provenance.verifyHostedRelease({
      receipt,
      run: fakeRunner(approvedRemote)
    })
    expectThrow(
      () => provenance.assertArtifactReceiptFiles(receipt, { zipPath, checksumPath }),
      /changed after approval/,
      'post-approval local mutations must be measured against the captured receipt'
    )
    fs.writeFileSync(zipPath, Buffer.from('deterministic fixture bytes'))
    fs.writeFileSync(checksumPath, `${hash(fs.readFileSync(zipPath))}  reflaxe.rust-${VERSION}.zip\n`)

    expectThrow(
      () =>
        provenance.verifyHostedRelease({
          receipt,
          run: fakeRunner(expectedRelease(zipPath, checksumPath, { wrongDigest: true }))
        }),
      /hosted asset digest does not match the approved file/
    )
    expectThrow(
      () =>
        provenance.verifyHostedRelease({
          receipt,
          run: fakeRunner(expectedRelease(zipPath, checksumPath, { extraAsset: true }))
        }),
      /hosted custom asset set does not match the release contract/
    )
    expectThrow(
      () =>
        provenance.verifyHostedRelease({
          receipt,
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

    const tagControls = {
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
    provenance.verifyHostTagControls({
      repository: 'fullofcaffeine/reflaxe.rust',
      run: identityRunner(tagControls)
    })
    expectThrow(
      () =>
        provenance.verifyHostTagControls({
          repository: 'fullofcaffeine/reflaxe.rust',
          run: identityRunner({
            ...tagControls,
            'gh api repos/fullofcaffeine/reflaxe.rust/rulesets/42': JSON.stringify({
              id: 42,
              target: 'tag',
              enforcement: 'active',
              conditions: { ref_name: { include: ['refs/tags/v*'], exclude: [] } },
              rules: [{ type: 'non_fast_forward' }]
            })
          })
        }),
      /semantic-version tag ruleset does not prevent update and deletion/
    )

    const controls = {
      'gh api repos/fullofcaffeine/reflaxe.rust/immutable-releases': JSON.stringify({ enabled: true }),
      ...tagControls
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

    const fakeGh = path.join(temp, 'gh')
    fs.writeFileSync(
      fakeGh,
      `#!/bin/sh
case "$*" in
  "api repos/fullofcaffeine/reflaxe.rust/immutable-releases") printf '%s' '{"enabled":true}' ;;
  "api repos/fullofcaffeine/reflaxe.rust/rulesets") printf '%s' '[{"id":42,"name":"Immutable semantic version tags","target":"tag","enforcement":"active"}]' ;;
  "api repos/fullofcaffeine/reflaxe.rust/rulesets/42") printf '%s' '{"id":42,"conditions":{"ref_name":{"include":["refs/tags/v*"]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"}]}' ;;
  *) exit 97 ;;
esac
`
    )
    fs.chmodSync(fakeGh, 0o755)
    const cliEnvironment = { ...process.env, PATH: `${temp}${path.delimiter}${process.env.PATH || ''}` }
    delete cliEnvironment.RELEASE_GH_BIN
    delete cliEnvironment.RELEASE_TEMP_ROOT
    delete cliEnvironment.TMP
    delete cliEnvironment.TMPDIR
    const tagAudit = execFileSync(
      process.execPath,
      [path.join(repoRoot, 'scripts', 'release', 'verify-host-tag-controls.js'), 'fullofcaffeine/reflaxe.rust'],
      { encoding: 'utf8', env: cliEnvironment }
    )
    assert.match(tagAudit, /immutable semantic-version tag ruleset 42/)
    const completeAudit = execFileSync(
      process.execPath,
      [path.join(repoRoot, 'scripts', 'release', 'verify-host-controls.js'), 'fullofcaffeine/reflaxe.rust'],
      { encoding: 'utf8', env: cliEnvironment }
    )
    assert.match(completeAudit, /immutable releases and tag ruleset 42/)

    const config = require(path.join(repoRoot, 'release.config.js'))
    const names = config.plugins.map((entry) => (Array.isArray(entry) ? entry[0] : entry))
    assert.deepStrictEqual(names, [
      './scripts/release/semantic-release-policy.cjs',
      '@semantic-release/release-notes-generator',
      './scripts/release/haxelib-artifact-plugin.cjs',
      './scripts/release/published-verifier-plugin.cjs'
    ])

    console.log('[release-provenance-test] OK')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

main()
