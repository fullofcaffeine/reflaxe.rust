const path = require('path')
const { normalizeSha, verifyHostedRelease, verifyTagIdentity } = require('./release-provenance.js')

function sourceCommit(cwd) {
  const { execFileSync } = require('child_process')
  const head = normalizeSha(
    execFileSync('git', ['rev-parse', 'HEAD^{commit}'], { cwd, encoding: 'utf8' }),
    'checked-out HEAD'
  )
  return process.env.GITHUB_SHA ? normalizeSha(process.env.GITHUB_SHA, 'GITHUB_SHA') : head
}

/** Verify the immutable hosted release after the GitHub publisher plugin completes. */
async function publish(_pluginConfig, context) {
  const cwd = context.cwd
  const source = sourceCommit(cwd)
  const version = context.nextRelease.version
  const tag = context.nextRelease.gitTag
  verifyTagIdentity({ tag, sourceCommit: source, cwd })
  verifyHostedRelease({
    version,
    tag,
    zipPath: path.join(cwd, 'dist', 'reflaxe.rust.zip'),
    checksumPath: path.join(cwd, 'dist', 'reflaxe.rust.zip.sha256'),
    cwd
  })
  context.logger.success(`Verified immutable hosted release ${tag} and both approved asset digests`)
}

module.exports = { publish }
