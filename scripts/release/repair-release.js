#!/usr/bin/env node

const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const { assertExactBootstrap, gitObject } = require('./exact-git-source.js')
const { loadReleasePolicy, verifyReleaseVersion } = require('./release-policy.js')
const {
  artifactNames,
  assertArtifactReceiptFiles,
  createArtifactReceipt,
  normalizeSha,
  verifyHostedDraft,
  verifyHostedRelease,
  verifyTagIdentity
} = require('./release-provenance.js')
const {
  assertTrackedTreeClean,
  buildFromReviewedSource,
  releaseProcessEnvironment,
  withReviewedSource
} = require('./reviewed-source.js')

const REPAIR_ENVIRONMENT_KEYS = [
  'GH_HOST',
  'GH_TOKEN',
  'GITHUB_API_URL',
  'GITHUB_REPOSITORY',
  'GITHUB_SERVER_URL',
  'GITHUB_TOKEN',
  'PACKAGE_SMOKE_USE_EXISTING',
  'PACKAGE_ZIP_REL'
]

function run(command, args, options = {}) {
  const environment = releaseProcessEnvironment(options.env || process.env, REPAIR_ENVIRONMENT_KEYS)
  const executable = {
    bash: environment.RELEASE_BASH_BIN,
    gh: environment.RELEASE_GH_BIN
  }[command] || command
  if (!executable) throw new Error(`reviewed release execution lacks an absolute ${command} tool`)
  return execFileSync(executable, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    env: environment,
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
  assertExactBootstrap(cwd, sourceCommit)
  assertTrackedTreeClean(cwd, 'repair checkout contains tracked changes')
  const dist = path.join(cwd, 'dist')
  const zipPath = path.join(dist, 'reflaxe.rust.zip')
  const checksumPath = path.join(dist, 'reflaxe.rust.zip.sha256')
  const repeatRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-repair-repeat-'))
  const repeatZip = path.join(repeatRoot, 'reflaxe.rust.zip')
  try {
    fs.mkdirSync(dist, { recursive: true })
    const verified = withReviewedSource(cwd, sourceCommit, (firstSourceRoot) =>
      withReviewedSource(cwd, sourceCommit, (secondSourceRoot) => {
        buildFromReviewedSource({
          sourceRoot: firstSourceRoot,
          zipPath,
          version,
          tag,
          sourceCommit
        })
        buildFromReviewedSource({
          sourceRoot: secondSourceRoot,
          zipPath: repeatZip,
          version,
          tag,
          sourceCommit,
          env: { ...process.env, TZ: 'UTC', TMPDIR: repeatRoot }
        })
        if (!fs.readFileSync(zipPath).equals(fs.readFileSync(repeatZip))) {
          throw new Error('repaired Haxelib package is not byte-for-byte reproducible')
        }
        const reviewedVerifier = require(
          path.join(firstSourceRoot, 'scripts', 'release', 'verify-release-artifact.js')
        )
        return reviewedVerifier.verifyReleaseArtifact({
          zipPath,
          canonicalZipPath: repeatZip,
          version,
          tag,
          sourceCommit,
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
      stdio: 'inherit'
    })
    const receipt = createArtifactReceipt({
      version,
      tag,
      sourceCommit,
      zipPath,
      checksumPath
    })
    if (receipt.archive.digest !== `sha256:${verified.sha256}` || receipt.archive.size !== verified.size) {
      throw new Error('package smoke changed the repaired release artifact')
    }
    return { checksumPath, names, receipt, verified, zipPath }
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
  const sourceCommit = normalizeSha(
    gitObject(cwd, ['rev-parse', 'HEAD^{commit}'], { encoding: 'utf8' }),
    'checked-out HEAD'
  )
  assertExactBootstrap(cwd, sourceCommit)
  verifyTagIdentity({ tag, sourceCommit, cwd })

  assertTrackedTreeClean(cwd, 'repair checkout contains tracked changes')
  const artifact = buildApprovedArtifact({ cwd, version, tag, sourceCommit })
  const existing = releaseView(tag, cwd)
  if (existing && existing.isPrerelease) {
    throw new Error(`refusing to modify prerelease draft ${tag}`)
  }
  if (existing && existing.isImmutable) {
    verifyHostedRelease({
      receipt: artifact.receipt,
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
  assertArtifactReceiptFiles(artifact.receipt, {
    zipPath: versionedZip,
    checksumPath: versionedChecksum
  })
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
  assertArtifactReceiptFiles(artifact.receipt, {
    zipPath: versionedZip,
    checksumPath: versionedChecksum
  })
  verifyHostedDraft({ receipt: artifact.receipt, cwd })
  run('gh', ['release', 'edit', tag, '--draft=false'], { cwd, stdio: 'inherit' })
  verifyHostedRelease({
    receipt: artifact.receipt,
    cwd
  })
  console.log(`[release-repair] completed immutable ${tag}`)
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[release-repair] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = { buildApprovedArtifact, main }
