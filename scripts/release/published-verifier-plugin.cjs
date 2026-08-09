const fs = require('fs')
const os = require('os')
const path = require('path')
const { assertExactBootstrap, gitObject } = require('./exact-git-source.js')
const { assertTrackedTreeClean } = require('./reviewed-source.js')
const {
  assertArtifactReceiptFiles,
  defaultRun,
  normalizeSha,
  readCapturedArtifactReceipt,
  verifyHostedDraft,
  verifyHostedRelease,
  verifyTagIdentity
} = require('./release-provenance.js')

function sourceCommit(cwd, allowedNewTag) {
  const head = normalizeSha(
    gitObject(cwd, ['rev-parse', 'HEAD^{commit}'], { encoding: 'utf8' }),
    'checked-out HEAD'
  )
  return process.env.GITHUB_SHA ? normalizeSha(process.env.GITHUB_SHA, 'GITHUB_SHA') : head
}

function releaseExists(tag, cwd) {
  try {
    defaultRun('gh', ['release', 'view', tag, '--json', 'tagName'], { cwd })
    return true
  } catch (_error) {
    return false
  }
}

/**
 * Why
 * A third-party publisher can read or change mutable `dist` files after they passed verification.
 * Recomputing the expected digest afterward only blesses that later state.
 *
 * What
 * Own the GitHub draft, upload, publication, and immutable hosted-byte check in the same reviewed
 * plugin that consumes the approval receipt written by the independent package rebuild.
 *
 * How
 * The plugin rejects any pre-existing release, copies files only after matching the receipt, checks
 * the upload copies again, publishes the draft, and compares GitHub's asset digests directly with
 * the captured approval identities. No intervening publisher receives the artifact paths.
 */
async function publish(_pluginConfig, context) {
  const cwd = context.cwd
  const source = sourceCommit(cwd, context.nextRelease.gitTag)
  assertExactBootstrap(cwd, source, process.env.RELEASE_EXPECTED_ORIGIN_URL, {
    allowedNewTag: context.nextRelease.gitTag
  })
  assertTrackedTreeClean(cwd, 'release publication modified tracked repository files')
  const receipt = readCapturedArtifactReceipt()
  if (
    receipt.sourceCommit !== source ||
    receipt.version !== context.nextRelease.version ||
    receipt.tag !== context.nextRelease.gitTag
  ) {
    throw new Error('approved artifact receipt does not match this release')
  }
  verifyTagIdentity({ tag: receipt.tag, sourceCommit: source, cwd })

  const zipPath = path.join(cwd, 'dist', 'reflaxe.rust.zip')
  const checksumPath = path.join(cwd, 'dist', 'reflaxe.rust.zip.sha256')
  assertArtifactReceiptFiles(receipt, { zipPath, checksumPath })
  if (releaseExists(receipt.tag, cwd)) {
    throw new Error(`GitHub Release ${receipt.tag} already exists; use the repair workflow`)
  }

  const stagingRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-hosted-upload-'))
  try {
    const notesPath = path.join(stagingRoot, 'release-notes.md')
    const versionedZip = path.join(stagingRoot, receipt.archive.name)
    const versionedChecksum = path.join(stagingRoot, receipt.checksum.name)
    fs.writeFileSync(notesPath, `${context.nextRelease.notes || ''}\n`)
    fs.copyFileSync(zipPath, versionedZip)
    fs.copyFileSync(checksumPath, versionedChecksum)
    assertArtifactReceiptFiles(receipt, {
      zipPath: versionedZip,
      checksumPath: versionedChecksum
    })

    defaultRun(
      'gh',
      [
        'release',
        'create',
        receipt.tag,
        '--verify-tag',
        '--draft',
        '--title',
        receipt.tag,
        '--notes-file',
        notesPath
      ],
      { cwd }
    )
    assertArtifactReceiptFiles(receipt, {
      zipPath: versionedZip,
      checksumPath: versionedChecksum
    })
    defaultRun(
      'gh',
      [
        'release',
        'upload',
        receipt.tag,
        `${versionedZip}#reflaxe.rust haxelib package`,
        `${versionedChecksum}#SHA-256 checksum`
      ],
      { cwd }
    )
    assertArtifactReceiptFiles(receipt, {
      zipPath: versionedZip,
      checksumPath: versionedChecksum
    })
    verifyHostedDraft({ receipt, cwd })
    defaultRun('gh', ['release', 'edit', receipt.tag, '--draft=false'], { cwd })
    verifyHostedRelease({ receipt, cwd })
  } finally {
    fs.rmSync(stagingRoot, { recursive: true, force: true })
  }
  context.logger.success(`Published and verified immutable hosted release ${receipt.tag}`)
}

module.exports = { publish }
