const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')
const {
  GIT_OUTPUT_MAX_BYTES,
  gitObjectEnvironment
} = require('./exact-git-source.js')
const { releaseProcessEnvironment } = require('./reviewed-source.js')

const HOST_ENVIRONMENT_KEYS = [
  'GH_HOST',
  'GH_TOKEN',
  'GITHUB_API_URL',
  'GITHUB_REPOSITORY',
  'GITHUB_SERVER_URL',
  'GITHUB_TOKEN'
]
let capturedArtifactReceipt = null

function defaultRun(command, args, options = {}) {
  const git = command === 'git'
  const environment = git
    ? gitObjectEnvironment(options.env || process.env)
    : releaseProcessEnvironment(options.env || process.env, HOST_ENVIRONMENT_KEYS)
  const executable = git
    ? (options.env || process.env).RELEASE_GIT_BIN || '/usr/bin/git'
    : environment.RELEASE_GH_BIN
  if (!path.isAbsolute(executable || '')) {
    throw new Error(`release ${command} executable must be an absolute path`)
  }
  return execFileSync(executable, git ? ['--no-replace-objects', ...args] : args, {
    cwd: options.cwd,
    encoding: 'utf8',
    env: environment,
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: GIT_OUTPUT_MAX_BYTES
  })
}

function normalizeSha(value, label) {
  const sha = String(value).trim().toLowerCase()
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error(`${label} is not a full Git commit SHA`)
  return sha
}

function fileIdentity(filePath) {
  const bytes = fs.readFileSync(filePath)
  return {
    digest: `sha256:${crypto.createHash('sha256').update(bytes).digest('hex')}`,
    size: bytes.length
  }
}

function artifactNames(version) {
  if (typeof version !== 'string' || !/^[0-9A-Za-z.+-]+$/.test(version)) {
    throw new Error('release version is not safe for an artifact name')
  }
  return {
    archive: `reflaxe.rust-${version}.zip`,
    checksum: `reflaxe.rust-${version}.zip.sha256`
  }
}

function createArtifactReceipt({ version, tag, sourceCommit, zipPath, checksumPath }) {
  const names = artifactNames(version)
  const archive = fileIdentity(zipPath)
  const checksum = fileIdentity(checksumPath)
  const checksumText = `${archive.digest.slice('sha256:'.length)}  ${names.archive}\n`
  if (fs.readFileSync(checksumPath, 'utf8') !== checksumText) {
    throw new Error('checksum sidecar does not identify the approved archive')
  }
  return {
    schemaVersion: 1,
    version,
    tag,
    sourceCommit: normalizeSha(sourceCommit, 'approved artifact source commit'),
    archive: { name: names.archive, ...archive },
    checksum: { name: names.checksum, ...checksum },
    checksumText
  }
}

function validateArtifactReceipt(receipt) {
  if (
    !receipt ||
    receipt.schemaVersion !== 1 ||
    typeof receipt.version !== 'string' ||
    receipt.tag !== `v${receipt.version}` ||
    !/^[0-9a-f]{40}$/.test(receipt.sourceCommit || '') ||
    !receipt.archive ||
    !receipt.checksum ||
    receipt.archive.name !== artifactNames(receipt.version).archive ||
    receipt.checksum.name !== artifactNames(receipt.version).checksum ||
    !/^sha256:[0-9a-f]{64}$/.test(receipt.archive.digest || '') ||
    !/^sha256:[0-9a-f]{64}$/.test(receipt.checksum.digest || '') ||
    !Number.isSafeInteger(receipt.archive.size) ||
    receipt.archive.size < 0 ||
    !Number.isSafeInteger(receipt.checksum.size) ||
    receipt.checksum.size < 0 ||
    receipt.checksumText !==
      `${receipt.archive.digest.slice('sha256:'.length)}  ${receipt.archive.name}\n`
  ) {
    throw new Error('approved artifact receipt is invalid')
  }
  return receipt
}

function assertArtifactReceiptFiles(receipt, { zipPath, checksumPath }) {
  validateArtifactReceipt(receipt)
  const archive = fileIdentity(zipPath)
  const checksum = fileIdentity(checksumPath)
  if (
    archive.digest !== receipt.archive.digest ||
    archive.size !== receipt.archive.size ||
    checksum.digest !== receipt.checksum.digest ||
    checksum.size !== receipt.checksum.size ||
    fs.readFileSync(checksumPath, 'utf8') !== receipt.checksumText
  ) {
    throw new Error('approved release artifact changed after approval')
  }
  return receipt
}

function captureArtifactReceipt(receipt) {
  const serialized = JSON.stringify(validateArtifactReceipt(receipt))
  if (capturedArtifactReceipt !== null && capturedArtifactReceipt !== serialized) {
    throw new Error('a later operation cannot replace the captured approval identity')
  }
  capturedArtifactReceipt = serialized
  return JSON.parse(serialized)
}

function readCapturedArtifactReceipt() {
  if (capturedArtifactReceipt === null) {
    throw new Error('approved artifact receipt was not captured in this release process')
  }
  return validateArtifactReceipt(JSON.parse(capturedArtifactReceipt))
}

/**
 * Why
 * Matching generated metadata is not commit identity. A version tag can otherwise identify source
 * B while the workflow publishes an artifact built from source A.
 *
 * What
 * Bind the checked-out HEAD, local tag, and remote tag to the exact CI-tested commit SHA.
 *
 * How
 * Resolve full commit objects locally and inspect the authoritative remote ref directly. Annotated
 * tags use their peeled `^{}` ref; lightweight tags resolve directly.
 */
function verifyTagIdentity({ tag, sourceCommit, cwd, run = defaultRun }) {
  const expected = normalizeSha(sourceCommit, 'CI-tested source commit')
  const head = normalizeSha(run('git', ['rev-parse', 'HEAD^{commit}'], { cwd }), 'checked-out HEAD')
  if (head !== expected) throw new Error('checked-out HEAD does not identify the CI-tested commit')

  const local = normalizeSha(
    run('git', ['rev-parse', `refs/tags/${tag}^{commit}`], { cwd }),
    'local release tag'
  )
  if (local !== expected) throw new Error('local release tag does not identify the CI-tested commit')

  const remoteOutput = run(
    'git',
    ['ls-remote', '--tags', 'origin', `refs/tags/${tag}`, `refs/tags/${tag}^{}`],
    { cwd }
  )
  const refs = new Map(
    String(remoteOutput)
      .trim()
      .split('\n')
      .filter(Boolean)
      .map((line) => {
        const [sha, ref] = line.split(/\s+/, 2)
        return [ref, normalizeSha(sha, 'remote release tag')]
      })
  )
  const remote = refs.get(`refs/tags/${tag}^{}`) || refs.get(`refs/tags/${tag}`)
  if (!remote) throw new Error('remote release tag is missing')
  if (remote !== expected) throw new Error('remote release tag does not identify the CI-tested commit')
  return expected
}

function verifyAsset(asset, expected, label) {
  if (!asset || asset.state !== 'uploaded') throw new Error(`${label} is not in uploaded state`)
  if (asset.size !== expected.size) throw new Error(`${label} size does not match the approved file`)
  if (asset.digest !== expected.digest) throw new Error(`${label} digest does not match the approved file`)
}

function hostedRelease(receipt, cwd, run) {
  const approved = validateArtifactReceipt(receipt)
  return {
    approved,
    release: JSON.parse(
      run(
        'gh',
        [
          'release',
          'view',
          approved.tag,
          '--json',
          'tagName,isDraft,isImmutable,isPrerelease,assets'
        ],
        { cwd }
      )
    )
  }
}

function verifyHostedAssetSet(release, approved, label) {
  const names = artifactNames(approved.version)
  const assets = Array.isArray(release.assets) ? release.assets : []
  const expectedNames = [names.archive, names.checksum].sort()
  const actualNames = assets.map(({ name }) => name).sort()
  if (JSON.stringify(actualNames) !== JSON.stringify(expectedNames)) {
    throw new Error(`${label} custom asset set does not match the release contract`)
  }
  const byName = new Map(assets.map((asset) => [asset.name, asset]))
  verifyAsset(byName.get(names.archive), approved.archive, `${label} asset`)
  verifyAsset(byName.get(names.checksum), approved.checksum, `${label} checksum asset`)
}

/** Verify the exact mutable draft immediately before the irreversible public transition. */
function verifyHostedDraft({ receipt, cwd, run = defaultRun }) {
  const { approved, release } = hostedRelease(receipt, cwd, run)
  if (release.tagName !== approved.tag) throw new Error('draft GitHub Release tag does not match')
  if (!release.isDraft) throw new Error('GitHub Release is no longer an editable draft')
  if (release.isPrerelease) throw new Error('GitHub Release draft unexpectedly uses prerelease status')
  if (release.isImmutable) throw new Error('GitHub Release draft is unexpectedly immutable')
  verifyHostedAssetSet(release, approved, 'draft hosted')
  return release
}

/**
 * Why
 * An asset name is not provenance. Publication completes only when GitHub reports the same bytes
 * that passed the exact-artifact checks before the tag was created.
 *
 * What
 * Verify the hosted release kind, immutability, exact custom asset set, uploaded states, lengths,
 * and SHA-256 digests against the captured approval receipt.
 *
 * How
 * Query GitHub after the source-owned publisher completes and compare API metadata to identities
 * captured before the upload boundary. Immutable releases make that successful comparison durable.
 */
function verifyHostedRelease({ receipt, cwd, run = defaultRun }) {
  const { approved, release } = hostedRelease(receipt, cwd, run)
  if (release.tagName !== approved.tag) throw new Error('published GitHub Release tag does not match')
  if (release.isDraft) throw new Error('published GitHub Release is still a draft')
  if (release.isPrerelease) throw new Error('published GitHub Release unexpectedly uses prerelease status')
  if (!release.isImmutable) throw new Error('published GitHub Release is not immutable')

  verifyHostedAssetSet(release, approved, 'hosted')
  return release
}

function verifyHostReleaseControls({ repository, cwd, run = defaultRun }) {
  if (typeof repository !== 'string' || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) {
    throw new Error('repository must use OWNER/NAME form')
  }
  const immutable = JSON.parse(run('gh', ['api', `repos/${repository}/immutable-releases`], { cwd }))
  if (!immutable.enabled) throw new Error('immutable GitHub Releases are not enabled')

  const summaries = JSON.parse(run('gh', ['api', `repos/${repository}/rulesets`], { cwd }))
  const summary = summaries.find(
    (entry) =>
      entry &&
      entry.name === 'Immutable semantic version tags' &&
      entry.target === 'tag' &&
      entry.enforcement === 'active'
  )
  if (!summary) throw new Error('active semantic-version tag immutability ruleset is missing')
  const ruleset = JSON.parse(run('gh', ['api', `repos/${repository}/rulesets/${summary.id}`], { cwd }))
  const includes = ruleset.conditions && ruleset.conditions.ref_name && ruleset.conditions.ref_name.include
  const types = new Set((ruleset.rules || []).map(({ type }) => type))
  if (
    !Array.isArray(includes) ||
    !includes.includes('refs/tags/v*') ||
    !types.has('deletion') ||
    !types.has('non_fast_forward')
  ) {
    throw new Error('semantic-version tag ruleset does not prevent update and deletion')
  }
  return { immutable, ruleset }
}

module.exports = {
  artifactNames,
  assertArtifactReceiptFiles,
  captureArtifactReceipt,
  createArtifactReceipt,
  defaultRun,
  fileIdentity,
  normalizeSha,
  readCapturedArtifactReceipt,
  verifyHostReleaseControls,
  verifyHostedDraft,
  verifyHostedRelease,
  verifyTagIdentity
}
