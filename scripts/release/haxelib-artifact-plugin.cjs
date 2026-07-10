const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const { verifyReleaseArtifact } = require('./verify-release-artifact.js')
const { artifactNames, normalizeSha, verifyTagIdentity } = require('./release-provenance.js')

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    env: options.env || process.env,
    stdio: options.stdio || 'inherit'
  })
}

function sourceCommit(cwd) {
  const head = normalizeSha(
    execFileSync('git', ['rev-parse', 'HEAD^{commit}'], { cwd, encoding: 'utf8' }),
    'checked-out HEAD'
  )
  const tested = process.env.GITHUB_SHA ? normalizeSha(process.env.GITHUB_SHA, 'GITHUB_SHA') : head
  if (head !== tested) throw new Error('release checkout does not match the CI-tested GITHUB_SHA')
  return tested
}

function assertTrackedTreeClean(cwd) {
  const status = execFileSync('git', ['status', '--porcelain', '--untracked-files=no'], {
    cwd,
    encoding: 'utf8'
  })
  if (status.trim().length > 0) throw new Error('release preparation modified tracked repository files')
}

function hash(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
}

/** Build twice, compare bytes, validate the complete archive, and smoke the exact first build. */
async function prepare(_pluginConfig, context) {
  const cwd = context.cwd
  const version = context.nextRelease.version
  const tag = context.nextRelease.gitTag
  const source = sourceCommit(cwd)
  const dist = path.join(cwd, 'dist')
  const zipPath = path.join(dist, 'reflaxe.rust.zip')
  const checksumPath = path.join(dist, 'reflaxe.rust.zip.sha256')
  const secondRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-release-repeat-'))
  const secondZip = path.join(secondRoot, 'reflaxe.rust.zip')

  try {
    assertTrackedTreeClean(cwd)
    fs.mkdirSync(dist, { recursive: true })
    fs.rmSync(zipPath, { force: true })
    fs.rmSync(checksumPath, { force: true })

    run('bash', ['scripts/release/package-haxelib.sh', zipPath, version, tag, source], { cwd })
    run('bash', ['scripts/release/package-haxelib.sh', secondZip, version, tag, source], {
      cwd,
      env: { ...process.env, TZ: 'UTC', TMPDIR: secondRoot }
    })
    if (!fs.readFileSync(zipPath).equals(fs.readFileSync(secondZip))) {
      throw new Error('complete Haxelib package is not byte-for-byte reproducible')
    }

    const verified = verifyReleaseArtifact({ zipPath, version, tag, sourceCommit: source })
    const names = artifactNames(version)
    fs.writeFileSync(checksumPath, `${verified.sha256}  ${names.archive}\n`)

    run('bash', ['scripts/ci/package-smoke.sh'], {
      cwd,
      env: {
        ...process.env,
        PACKAGE_SMOKE_USE_EXISTING: '1',
        PACKAGE_ZIP_REL: path.relative(cwd, zipPath)
      }
    })
    assertTrackedTreeClean(cwd)
    context.logger.success(
      `Prepared reproducible ${names.archive} (${verified.size} bytes, sha256:${verified.sha256}) from ${source}`
    )
  } finally {
    fs.rmSync(secondRoot, { recursive: true, force: true })
  }
}

/** semantic-release calls publish after it has created and pushed the tag, before GitHub upload. */
async function publish(_pluginConfig, context) {
  const cwd = context.cwd
  const version = context.nextRelease.version
  const tag = context.nextRelease.gitTag
  const source = sourceCommit(cwd)
  verifyTagIdentity({ tag, sourceCommit: source, cwd })
  const zipPath = path.join(cwd, 'dist', 'reflaxe.rust.zip')
  const verified = verifyReleaseArtifact({ zipPath, version, tag, sourceCommit: source })
  const checksumPath = path.join(cwd, 'dist', 'reflaxe.rust.zip.sha256')
  const names = artifactNames(version)
  const expectedChecksum = `${verified.sha256}  ${names.archive}\n`
  if (
    hash(zipPath) !== verified.sha256 ||
    !fs.existsSync(checksumPath) ||
    fs.readFileSync(checksumPath, 'utf8') !== expectedChecksum
  ) {
    throw new Error('approved release artifact changed after preparation')
  }
  assertTrackedTreeClean(cwd)
  context.logger.success(`Verified ${tag} and the approved artifact before GitHub publication`)
}

module.exports = { prepare, publish }
