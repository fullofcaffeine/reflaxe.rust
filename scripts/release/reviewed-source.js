const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const {
  assertPackageInputsTracked,
  isReleaseInput
} = require('./package-input-cleanliness.js')
const {
  GIT_OUTPUT_MAX_BYTES,
  commitEntries,
  gitObject,
  materializeCommit,
  reviewedCommit
} = require('./exact-git-source.js')

const RELEASE_ENVIRONMENT_KEYS = [
  'COMSPEC',
  'HAXE_LIBCACHE',
  'HAXE_LIBRARY_PATH',
  'HAXE_STD_PATH',
  'HOME',
  'LANG',
  'LC_ALL',
  'LC_CTYPE',
  'PATH',
  'PATHEXT',
  'SYSTEMROOT',
  'TEMP',
  'TMP',
  'TMPDIR',
  'TZ',
  'WINDIR'
]

function releaseProcessEnvironment(source, additionalKeys = []) {
  const environment = {}
  for (const key of [...RELEASE_ENVIRONMENT_KEYS, ...additionalKeys]) {
    if (source[key] !== undefined) environment[key] = source[key]
  }
  if (!environment.PATH) throw new Error('reviewed release execution requires an explicit PATH')
  return environment
}

function assertCommitReleaseInputModes(repositoryRoot, sourceCommit) {
  const invalid = []
  for (const { file, mode, type } of commitEntries(repositoryRoot, sourceCommit)) {
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
 * Git enumerates the committed tree with replacement objects disabled, then each permitted regular
 * blob is read by object ID and written into an empty directory. Archive attributes, checkout
 * filters, and the live worktree never participate. Cleanup runs even when the caller rejects the
 * build.
 */
function withReviewedSource(repositoryRoot, sourceCommit, operation) {
  const commit = reviewedCommit(repositoryRoot, sourceCommit)
  assertCommitReleaseInputModes(repositoryRoot, commit)
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-reviewed-source-'))
  const sourceRoot = path.join(temporaryRoot, 'source')
  try {
    fs.mkdirSync(sourceRoot)
    materializeCommit(repositoryRoot, commit, sourceRoot)
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
    {
      cwd: sourceRoot,
      env: releaseProcessEnvironment(env),
      stdio,
      maxBuffer: GIT_OUTPUT_MAX_BYTES
    }
  )
}

/** Keep large repository status output inside the shared explicit process bound. */
function assertTrackedTreeClean(repositoryRoot, message) {
  const status = gitObject(repositoryRoot, ['status', '--porcelain', '--untracked-files=no'], {
    encoding: 'utf8',
  })
  if (status.trim().length > 0) throw new Error(message)
  assertPackageInputsTracked(repositoryRoot)
}

module.exports = {
  assertCommitReleaseInputModes,
  assertTrackedTreeClean,
  buildFromReviewedSource,
  commitEntries,
  materializeCommit,
  releaseProcessEnvironment,
  reviewedCommit,
  withReviewedSource
}
