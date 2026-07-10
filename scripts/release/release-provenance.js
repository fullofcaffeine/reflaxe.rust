const crypto = require('crypto')
const fs = require('fs')
const { execFileSync } = require('child_process')

function defaultRun(command, args, options = {}) {
  return execFileSync(command, args, {
    cwd: options.cwd,
    encoding: 'utf8',
    env: options.env || process.env,
    stdio: ['ignore', 'pipe', 'pipe']
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

/**
 * Why
 * An asset name is not provenance. Publication completes only when GitHub reports the same bytes
 * that passed the exact-artifact checks before the tag was created.
 *
 * What
 * Verify the hosted release kind, immutability, exact custom asset set, uploaded states, lengths,
 * and SHA-256 digests against the local approved ZIP and checksum sidecar.
 *
 * How
 * Query GitHub after its publisher plugin completes and compare API metadata to locally calculated
 * identities. Immutable releases make that successful comparison durable for future consumers.
 */
function verifyHostedRelease({ version, tag, zipPath, checksumPath, cwd, run = defaultRun }) {
  const names = artifactNames(version)
  const zipIdentity = fileIdentity(zipPath)
  const checksumIdentity = fileIdentity(checksumPath)
  const expectedChecksum = `${zipIdentity.digest.slice('sha256:'.length)}  ${names.archive}\n`
  if (fs.readFileSync(checksumPath, 'utf8') !== expectedChecksum) {
    throw new Error('checksum sidecar does not identify the approved archive')
  }

  const release = JSON.parse(
    run(
      'gh',
      [
        'release',
        'view',
        tag,
        '--json',
        'tagName,isDraft,isImmutable,isPrerelease,assets'
      ],
      { cwd }
    )
  )
  if (release.tagName !== tag) throw new Error('published GitHub Release tag does not match')
  if (release.isDraft) throw new Error('published GitHub Release is still a draft')
  if (release.isPrerelease) throw new Error('published GitHub Release unexpectedly uses prerelease status')
  if (!release.isImmutable) throw new Error('published GitHub Release is not immutable')

  const assets = Array.isArray(release.assets) ? release.assets : []
  const expectedNames = [names.archive, names.checksum].sort()
  const actualNames = assets.map(({ name }) => name).sort()
  if (JSON.stringify(actualNames) !== JSON.stringify(expectedNames)) {
    throw new Error('hosted custom asset set does not match the release contract')
  }
  const byName = new Map(assets.map((asset) => [asset.name, asset]))
  verifyAsset(byName.get(names.archive), zipIdentity, 'hosted asset')
  verifyAsset(byName.get(names.checksum), checksumIdentity, 'hosted checksum asset')
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
  defaultRun,
  fileIdentity,
  normalizeSha,
  verifyHostReleaseControls,
  verifyHostedRelease,
  verifyTagIdentity
}
