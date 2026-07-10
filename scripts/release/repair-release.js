#!/usr/bin/env node

const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const { loadReleasePolicy, verifyReleaseVersion } = require('./release-policy.js')
const { verifyReleaseArtifact } = require('./verify-release-artifact.js')
const { artifactNames, normalizeSha, verifyHostedRelease, verifyTagIdentity } = require('./release-provenance.js')

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    env: options.env || process.env,
    stdio: options.stdio || ['ignore', 'pipe', 'pipe']
  })
}

function releaseView(tag, cwd) {
  try {
    return JSON.parse(
      run('gh', ['release', 'view', tag, '--json', 'tagName,isDraft,isImmutable,isPrerelease,assets'], { cwd })
    )
  } catch (_error) {
    return null
  }
}

function buildApprovedArtifact({ cwd, version, tag, sourceCommit }) {
  const dist = path.join(cwd, 'dist')
  const zipPath = path.join(dist, 'reflaxe.rust.zip')
  const checksumPath = path.join(dist, 'reflaxe.rust.zip.sha256')
  const repeatRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-repair-repeat-'))
  const repeatZip = path.join(repeatRoot, 'reflaxe.rust.zip')
  try {
    fs.mkdirSync(dist, { recursive: true })
    run('bash', ['scripts/release/package-haxelib.sh', zipPath, version, tag, sourceCommit], {
      cwd,
      stdio: 'inherit'
    })
    run('bash', ['scripts/release/package-haxelib.sh', repeatZip, version, tag, sourceCommit], {
      cwd,
      env: { ...process.env, TZ: 'UTC', TMPDIR: repeatRoot },
      stdio: 'inherit'
    })
    if (!fs.readFileSync(zipPath).equals(fs.readFileSync(repeatZip))) {
      throw new Error('repaired Haxelib package is not byte-for-byte reproducible')
    }
    const verified = verifyReleaseArtifact({ zipPath, version, tag, sourceCommit })
    const names = artifactNames(version)
    fs.writeFileSync(checksumPath, `${verified.sha256}  ${names.archive}\n`)
    run('bash', ['scripts/ci/package-smoke.sh'], {
      cwd,
      env: {
        ...process.env,
        PACKAGE_SMOKE_USE_EXISTING: '1',
        PACKAGE_ZIP_REL: path.relative(cwd, zipPath)
      },
      stdio: 'inherit'
    })
    return { checksumPath, names, verified, zipPath }
  } finally {
    fs.rmSync(repeatRoot, { recursive: true, force: true })
  }
}

/**
 * Why
 * A valid remote tag can outlive a failed GitHub draft/upload request. Normal semantic-release must
 * not analyze commits again or create another version to repair that external partial state.
 *
 * What
 * Rebuild and verify the deterministic artifact for one supplied existing tag, complete only its
 * draft Release, publish it, and verify immutable hosted digests.
 *
 * How
 * The command refuses branch/SHA input, never creates or changes a tag, binds local and remote tag
 * identity first, and permits mutation only while the associated Release is absent or still draft.
 */
function main() {
  const [tag, ...rest] = process.argv.slice(2)
  if (!tag || rest.length > 0 || !/^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(tag)) {
    throw new Error('usage: repair-release.js <existing vMAJOR.MINOR.PATCH tag>')
  }
  const cwd = path.resolve(__dirname, '..', '..')
  const version = tag.slice(1)
  verifyReleaseVersion(loadReleasePolicy(path.join(cwd, 'release-manifest.json')), version)
  const sourceCommit = normalizeSha(run('git', ['rev-parse', 'HEAD^{commit}'], { cwd }), 'checked-out HEAD')
  verifyTagIdentity({ tag, sourceCommit, cwd })

  const tracked = run('git', ['status', '--porcelain', '--untracked-files=no'], { cwd })
  if (tracked.trim().length > 0) throw new Error('repair checkout contains tracked changes')
  const artifact = buildApprovedArtifact({ cwd, version, tag, sourceCommit })
  const existing = releaseView(tag, cwd)
  if (existing && existing.isImmutable) {
    verifyHostedRelease({
      version,
      tag,
      zipPath: artifact.zipPath,
      checksumPath: artifact.checksumPath,
      cwd
    })
    console.log(`[release-repair] ${tag} is already complete and immutable`)
    return
  }
  if (existing && !existing.isDraft) {
    throw new Error(`refusing to modify already-published mutable release ${tag}`)
  }
  if (!existing) {
    run('gh', ['release', 'create', tag, '--verify-tag', '--draft', '--generate-notes', '--title', tag], {
      cwd,
      stdio: 'inherit'
    })
  } else {
    for (const asset of existing.assets || []) {
      run('gh', ['release', 'delete-asset', tag, asset.name, '--yes'], { cwd, stdio: 'inherit' })
    }
  }

  const versionedZip = path.join(cwd, 'dist', artifact.names.archive)
  const versionedChecksum = path.join(cwd, 'dist', artifact.names.checksum)
  fs.copyFileSync(artifact.zipPath, versionedZip)
  fs.copyFileSync(artifact.checksumPath, versionedChecksum)
  run(
    'gh',
    [
      'release',
      'upload',
      tag,
      `${versionedZip}#reflaxe.rust haxelib package`,
      `${versionedChecksum}#SHA-256 checksum`,
      '--clobber'
    ],
    { cwd, stdio: 'inherit' }
  )
  run('gh', ['release', 'edit', tag, '--draft=false'], { cwd, stdio: 'inherit' })
  verifyHostedRelease({
    version,
    tag,
    zipPath: artifact.zipPath,
    checksumPath: artifact.checksumPath,
    cwd
  })
  console.log(`[release-repair] completed immutable ${tag}`)
}

try {
  main()
} catch (error) {
  console.error(`[release-repair] ERROR: ${error.message}`)
  process.exit(1)
}
