const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const { artifactNames, normalizeSha, verifyTagIdentity } = require('./release-provenance.js')
const { assertExactBootstrap, gitObject } = require('./exact-git-source.js')
const {
  assertTrackedTreeClean,
  buildFromReviewedSource,
  releaseProcessEnvironment,
  withReviewedSource
} = require('./reviewed-source.js')

function run(command, args, options = {}) {
  return execFileSync(command, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    env: releaseProcessEnvironment(
      options.env || process.env,
      options.additionalEnvironmentKeys || []
    ),
    stdio: options.stdio || 'inherit'
  })
}

function sourceCommit(cwd) {
  const head = normalizeSha(
    gitObject(cwd, ['rev-parse', 'HEAD^{commit}'], { encoding: 'utf8' }),
    'checked-out HEAD'
  )
  const tested = process.env.GITHUB_SHA ? normalizeSha(process.env.GITHUB_SHA, 'GITHUB_SHA') : head
  if (head !== tested) throw new Error('release checkout does not match the CI-tested GITHUB_SHA')
  assertExactBootstrap(cwd, tested)
  return tested
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
    assertTrackedTreeClean(cwd, 'release preparation modified tracked repository files')
    fs.mkdirSync(dist, { recursive: true })
    fs.rmSync(zipPath, { force: true })
    fs.rmSync(checksumPath, { force: true })

    const verified = withReviewedSource(cwd, source, (firstSourceRoot) =>
      withReviewedSource(cwd, source, (secondSourceRoot) => {
        buildFromReviewedSource({
          sourceRoot: firstSourceRoot,
          zipPath,
          version,
          tag,
          sourceCommit: source
        })
        buildFromReviewedSource({
          sourceRoot: secondSourceRoot,
          zipPath: secondZip,
          version,
          tag,
          sourceCommit: source,
          env: { ...process.env, TZ: 'UTC', TMPDIR: secondRoot }
        })
        if (!fs.readFileSync(zipPath).equals(fs.readFileSync(secondZip))) {
          throw new Error('complete Haxelib package is not byte-for-byte reproducible')
        }
        const reviewedVerifier = require(
          path.join(firstSourceRoot, 'scripts', 'release', 'verify-release-artifact.js')
        )
        return reviewedVerifier.verifyReleaseArtifact({
          zipPath,
          canonicalZipPath: secondZip,
          version,
          tag,
          sourceCommit: source,
          sourceRoot: firstSourceRoot
        })
      })
    )
    const names = artifactNames(version)
    fs.writeFileSync(checksumPath, `${verified.sha256}  ${names.archive}\n`)

    run('bash', ['scripts/ci/package-smoke.sh'], {
      cwd,
      env: {
        ...process.env,
        PACKAGE_SMOKE_USE_EXISTING: '1',
        PACKAGE_ZIP_REL: path.relative(cwd, zipPath)
      },
      additionalEnvironmentKeys: ['PACKAGE_SMOKE_USE_EXISTING', 'PACKAGE_ZIP_REL']
    })
    assertTrackedTreeClean(cwd, 'release preparation modified tracked repository files')
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
  const canonicalRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-release-publish-'))
  const canonicalZipPath = path.join(canonicalRoot, 'reflaxe.rust.zip')
  let verified
  try {
    assertTrackedTreeClean(cwd, 'release publication modified tracked repository files')
    verified = withReviewedSource(cwd, source, (sourceRoot) => {
      buildFromReviewedSource({
        sourceRoot,
        zipPath: canonicalZipPath,
        version,
        tag,
        sourceCommit: source,
        env: { ...process.env, TZ: 'UTC', TMPDIR: canonicalRoot }
      })
      const reviewedVerifier = require(
        path.join(sourceRoot, 'scripts', 'release', 'verify-release-artifact.js')
      )
      return reviewedVerifier.verifyReleaseArtifact({
        zipPath,
        canonicalZipPath,
        version,
        tag,
        sourceCommit: source,
        sourceRoot
      })
    })
  } finally {
    fs.rmSync(canonicalRoot, { recursive: true, force: true })
  }
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
  assertTrackedTreeClean(cwd, 'release publication modified tracked repository files')
  context.logger.success(`Verified ${tag} and the approved artifact before GitHub publication`)
}

module.exports = { prepare, publish }
