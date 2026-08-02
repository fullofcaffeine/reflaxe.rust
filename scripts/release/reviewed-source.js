const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const {
  assertPackageInputsTracked,
  GIT_OUTPUT_MAX_BYTES,
  isReleaseInput
} = require('./package-input-cleanliness.js')

function reviewedCommit(repositoryRoot, sourceCommit) {
  if (!/^[0-9a-f]{40}$/.test(sourceCommit || '')) {
    throw new Error('reviewed release source must be an exact lowercase Git commit')
  }
  const resolved = execFileSync('git', ['rev-parse', `${sourceCommit}^{commit}`], {
    cwd: repositoryRoot,
    encoding: 'utf8',
    maxBuffer: GIT_OUTPUT_MAX_BYTES
  }).trim()
  if (resolved !== sourceCommit) {
    throw new Error('reviewed release source does not resolve to the named exact commit')
  }
  return resolved
}

function assertCommitReleaseInputModes(repositoryRoot, sourceCommit) {
  const output = execFileSync(
    'git',
    ['ls-tree', '-r', '-z', '--full-tree', sourceCommit],
    { cwd: repositoryRoot, maxBuffer: GIT_OUTPUT_MAX_BYTES }
  ).toString('utf8')
  const invalid = []
  for (const record of output.split('\0').filter(Boolean)) {
    const separator = record.indexOf('\t')
    if (separator < 0) throw new Error('Git returned malformed reviewed-tree data')
    const [mode, type] = record.slice(0, separator).split(' ')
    const file = record.slice(separator + 1)
    if (
      isReleaseInput(file) &&
      (type !== 'blob' || (mode !== '100644' && mode !== '100755'))
    ) {
      invalid.push(file)
    }
  }
  if (invalid.length > 0) {
    throw new Error(
      `reviewed release input must be a regular Git blob: ${invalid.sort().join(', ')}`
    )
  }
}

/**
 * Why
 * A clean Git status does not prove that live worktree bytes match a commit: `assume-unchanged`,
 * `skip-worktree`, checkout filters, and line-ending conversion can all hide or transform bytes.
 * Building twice from that same checkout would reproduce the same wrong package.
 *
 * What
 * Materialize the exact tree named by `sourceCommit` into a fresh temporary directory and give that
 * directory to one synchronous release operation.
 *
 * How
 * Git writes the committed tree to an archive, the helper extracts it into an empty directory, and
 * release-owned paths are required to be ordinary Git blobs. The checkout's `node_modules` may be
 * linked as a tool dependency, but package construction never copies that directory. Cleanup runs
 * even when the caller rejects the build.
 */
function withReviewedSource(repositoryRoot, sourceCommit, operation) {
  const commit = reviewedCommit(repositoryRoot, sourceCommit)
  assertCommitReleaseInputModes(repositoryRoot, commit)
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-reviewed-source-'))
  const archivePath = path.join(temporaryRoot, 'source.tar')
  const sourceRoot = path.join(temporaryRoot, 'source')
  try {
    fs.mkdirSync(sourceRoot)
    execFileSync(
      'git',
      ['archive', '--format=tar', `--output=${archivePath}`, commit],
      { cwd: repositoryRoot, maxBuffer: GIT_OUTPUT_MAX_BYTES }
    )
    execFileSync('tar', ['-xf', archivePath, '-C', sourceRoot], {
      maxBuffer: GIT_OUTPUT_MAX_BYTES
    })
    const toolModules = path.join(repositoryRoot, 'node_modules')
    if (fs.existsSync(toolModules)) {
      fs.symlinkSync(toolModules, path.join(sourceRoot, 'node_modules'), 'dir')
    }
    return operation(sourceRoot)
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true })
  }
}

/** Run the package transformation whose source code and input bytes both came from one commit. */
function buildFromReviewedSource({
  sourceRoot,
  zipPath,
  version,
  tag,
  sourceCommit,
  env = process.env,
  stdio = 'inherit'
}) {
  return execFileSync(
    'bash',
    [
      path.join(sourceRoot, 'scripts', 'release', 'package-haxelib.sh'),
      zipPath,
      version,
      tag,
      sourceCommit
    ],
    { cwd: sourceRoot, env, stdio, maxBuffer: GIT_OUTPUT_MAX_BYTES }
  )
}

/** Keep large repository status output inside the shared explicit process bound. */
function assertTrackedTreeClean(repositoryRoot, message) {
  const status = execFileSync('git', ['status', '--porcelain', '--untracked-files=no'], {
    cwd: repositoryRoot,
    encoding: 'utf8',
    maxBuffer: GIT_OUTPUT_MAX_BYTES
  })
  if (status.trim().length > 0) throw new Error(message)
  assertPackageInputsTracked(repositoryRoot)
}

module.exports = {
  assertCommitReleaseInputModes,
  assertTrackedTreeClean,
  buildFromReviewedSource,
  reviewedCommit,
  withReviewedSource
}
