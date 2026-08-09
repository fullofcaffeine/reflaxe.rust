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
  'CI',
  'GITHUB_ACTIONS',
  'GITHUB_EVENT_NAME',
  'GITHUB_REF',
  'GITHUB_SHA',
  'GIT_ATTR_NOSYSTEM',
  'GIT_CONFIG_GLOBAL',
  'GIT_CONFIG_NOSYSTEM',
  'GIT_NO_REPLACE_OBJECTS',
  'LANG',
  'LC_ALL',
  'LC_CTYPE',
  'PATHEXT',
  'RELEASE_BASH_BIN',
  'RELEASE_CARGO_BIN',
  'RELEASE_CARGO_HOME',
  'RELEASE_EXPECTED_ORIGIN_URL',
  'RELEASE_GH_BIN',
  'RELEASE_GIT_BIN',
  'RELEASE_GIT_GUARD_BIN',
  'RELEASE_HAXE_BIN',
  'RELEASE_HAXELIB_BIN',
  'RELEASE_HOME',
  'RELEASE_NODE_BIN',
  'RELEASE_NPM_BIN',
  'RELEASE_RUSTC_BIN',
  'RELEASE_APPROVED_TAG',
  'RELEASE_STRICT_EXECUTION',
  'RELEASE_TEMP_ROOT',
  'RELEASE_TOOL_DIR',
  'SYSTEMROOT',
  'TEMP',
  'TZ',
  'WINDIR'
]

const TOOL_FALLBACKS = Object.freeze({
  RELEASE_BASH_BIN: process.platform === 'win32' ? null : '/bin/bash',
  RELEASE_GIT_BIN: process.platform === 'win32' ? null : '/usr/bin/git',
  RELEASE_NODE_BIN: process.execPath
})

function assertAbsoluteTool(environment, key, required) {
  let executable = environment[key] || TOOL_FALLBACKS[key]
  if (!executable && environment.RELEASE_STRICT_EXECUTION !== '1' && process.platform !== 'win32') {
    const command = {
      RELEASE_CARGO_BIN: 'cargo',
      RELEASE_GH_BIN: 'gh',
      RELEASE_HAXE_BIN: 'haxe',
      RELEASE_HAXELIB_BIN: 'haxelib',
      RELEASE_NPM_BIN: 'npm',
      RELEASE_RUSTC_BIN: 'rustc'
    }[key]
    if (command) {
      try {
        executable = execFileSync('/usr/bin/which', [command], { encoding: 'utf8' }).trim()
      } catch (_error) {
        executable = null
      }
    }
  }
  if (!executable) {
    if (required) throw new Error(`reviewed release execution requires ${key}`)
    return
  }
  if (!path.isAbsolute(executable) || !fs.statSync(executable).isFile()) {
    throw new Error(`${key} must name an absolute regular executable`)
  }
  fs.accessSync(executable, fs.constants.X_OK)
  environment[key] = executable
}

function releaseProcessEnvironment(source, additionalKeys = []) {
  const environment = {}
  for (const key of [...RELEASE_ENVIRONMENT_KEYS, ...additionalKeys]) {
    if (source[key] !== undefined) environment[key] = source[key]
  }
  const strict = environment.RELEASE_STRICT_EXECUTION === '1'
  for (const key of ['RELEASE_BASH_BIN', 'RELEASE_GIT_BIN', 'RELEASE_NODE_BIN']) {
    assertAbsoluteTool(environment, key, true)
  }
  for (const key of [
    'RELEASE_CARGO_BIN',
    'RELEASE_HAXE_BIN',
    'RELEASE_HAXELIB_BIN',
    'RELEASE_NPM_BIN',
    'RELEASE_RUSTC_BIN'
  ]) {
    assertAbsoluteTool(environment, key, strict)
  }
  if (environment.RELEASE_GH_BIN !== undefined) {
    assertAbsoluteTool(environment, 'RELEASE_GH_BIN', true)
  }
  const home = environment.RELEASE_HOME || (!strict ? source.HOME : null)
  const temporary = environment.RELEASE_TEMP_ROOT || (!strict ? (source.TMPDIR || source.TMP) : null)
  if (!home || !path.isAbsolute(home)) throw new Error('reviewed release execution requires an absolute RELEASE_HOME')
  if (!temporary || !path.isAbsolute(temporary)) {
    throw new Error('reviewed release execution requires an absolute RELEASE_TEMP_ROOT')
  }
  environment.HOME = home
  environment.GIT_ATTR_NOSYSTEM = '1'
  environment.GIT_CONFIG_GLOBAL = process.platform === 'win32' ? 'NUL' : '/dev/null'
  environment.GIT_CONFIG_NOSYSTEM = '1'
  environment.GIT_NO_REPLACE_OBJECTS = '1'
  if (environment.RELEASE_CARGO_HOME !== undefined) {
    if (!path.isAbsolute(environment.RELEASE_CARGO_HOME)) {
      throw new Error('RELEASE_CARGO_HOME must be absolute')
    }
    environment.CARGO_HOME = environment.RELEASE_CARGO_HOME
  } else if (strict) {
    throw new Error('reviewed release execution requires RELEASE_CARGO_HOME')
  }
  if (environment.RELEASE_RUSTC_BIN) environment.RUSTC = environment.RELEASE_RUSTC_BIN
  environment.TMP = temporary
  environment.TMPDIR = temporary
  if (environment.RELEASE_TOOL_DIR !== undefined) {
    if (!path.isAbsolute(environment.RELEASE_TOOL_DIR) || !fs.statSync(environment.RELEASE_TOOL_DIR).isDirectory()) {
      throw new Error('RELEASE_TOOL_DIR must be an absolute directory')
    }
    const expected = new Map([
      ['haxe', environment.RELEASE_HAXE_BIN],
      ['haxelib', environment.RELEASE_HAXELIB_BIN],
      ['node', environment.RELEASE_NODE_BIN]
    ])
    if (strict || environment.RELEASE_GIT_GUARD_BIN !== undefined) {
      assertAbsoluteTool(environment, 'RELEASE_GIT_GUARD_BIN', true)
      expected.set('git', environment.RELEASE_GIT_GUARD_BIN)
    }
    const entries = fs.readdirSync(environment.RELEASE_TOOL_DIR).sort()
    if (JSON.stringify(entries) !== JSON.stringify([...expected.keys()].sort())) {
      throw new Error('RELEASE_TOOL_DIR exposes an unexpected reviewed-tool set')
    }
    for (const [name, executable] of expected) {
      if (!executable || fs.realpathSync(path.join(environment.RELEASE_TOOL_DIR, name)) !== fs.realpathSync(executable)) {
        throw new Error(`RELEASE_TOOL_DIR ${name} does not match its reviewed executable`)
      }
    }
  } else if (strict) {
    throw new Error('reviewed release execution requires RELEASE_TOOL_DIR')
  }
  environment.PATH = process.platform === 'win32'
    ? ''
    : `${environment.RELEASE_TOOL_DIR ? `${environment.RELEASE_TOOL_DIR}:` : ''}/usr/bin:/bin`
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
  const environment = releaseProcessEnvironment(env)
  return execFileSync(
    environment.RELEASE_BASH_BIN,
    [
      path.join(sourceRoot, 'scripts', 'release', 'package-haxelib.sh'),
      zipPath,
      version,
      tag,
      sourceCommit
    ],
    {
      cwd: sourceRoot,
      env: environment,
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
