#!/usr/bin/env node

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')

const GIT_OUTPUT_MAX_BYTES = 64 * 1024 * 1024
const BOOTSTRAP_RECEIPT = 'haxe-rust-exact-source.json'
const GIT_ENVIRONMENT_KEYS = [
  'COMSPEC',
  'LANG',
  'LC_ALL',
  'LC_CTYPE',
  'PATHEXT',
  'SYSTEMROOT',
  'TEMP',
  'TMP',
  'TMPDIR',
  'WINDIR'
]
const PRELOAD_PROTECTED_PATHS = [
  '.releaserc',
  '.releaserc.cjs',
  '.releaserc.js',
  '.releaserc.json',
  '.releaserc.mjs',
  '.releaserc.yaml',
  '.releaserc.yml',
  'package-lock.json',
  'package.json',
  'release.config.cjs',
  'release.config.js',
  'release.config.mjs',
  'release-manifest.json',
  'scripts/ci',
  'scripts/release'
]

/**
 * Why
 * Ordinary Git commands may honor replacement refs, global configuration, or administrative files
 * that are not part of the commit named in release metadata. Two builds can then reproduce the same
 * substituted tree while still printing the reviewed commit ID.
 *
 * What
 * Provide the one self-contained exact-object reader used by release workflows and package rebuilds.
 * It resolves commits with replacement objects disabled and writes only literal regular blobs.
 *
 * How
 * A minimal Git environment drops caller-supplied repository/object/config controls. Tree entries are
 * enumerated without checkout or archive transformations, blob bytes are read in bounded batches by
 * object ID, and executable mode is copied explicitly.
 */
function gitObjectEnvironment(source = process.env) {
  const environment = {}
  for (const key of GIT_ENVIRONMENT_KEYS) {
    if (source[key] !== undefined) environment[key] = source[key]
  }
  environment.GIT_ATTR_NOSYSTEM = '1'
  environment.GIT_CONFIG_NOSYSTEM = '1'
  environment.GIT_CONFIG_GLOBAL = process.platform === 'win32' ? 'NUL' : '/dev/null'
  environment.GIT_NO_REPLACE_OBJECTS = '1'
  return environment
}

function gitBinary(source = process.env) {
  const configured = source.RELEASE_GIT_BIN
  if (configured !== undefined) {
    if (!path.isAbsolute(configured)) {
      throw new Error('RELEASE_GIT_BIN must be an absolute path')
    }
    return configured
  }
  if (process.platform !== 'win32' && fs.existsSync('/usr/bin/git')) return '/usr/bin/git'
  throw new Error('exact release verification requires an absolute RELEASE_GIT_BIN')
}

function gitObject(repositoryRoot, args, options = {}) {
  const { env: sourceEnvironment = process.env, ...executionOptions } = options
  return execFileSync(gitBinary(sourceEnvironment), ['--no-replace-objects', ...args], {
    cwd: repositoryRoot,
    env: gitObjectEnvironment(sourceEnvironment),
    maxBuffer: GIT_OUTPUT_MAX_BYTES,
    ...executionOptions
  })
}

function resolvedGitPath(repositoryRoot, argument) {
  return fs.realpathSync(
    path.resolve(
      repositoryRoot,
      gitObject(repositoryRoot, ['rev-parse', argument], { encoding: 'utf8' }).trim()
    )
  )
}

function gitDirectory(repositoryRoot) {
  return resolvedGitPath(repositoryRoot, '--git-dir')
}

function gitCommonDirectory(repositoryRoot) {
  return resolvedGitPath(repositoryRoot, '--git-common-dir')
}

/** A release checkout owns one administration directory; linked worktrees are deliberately unsupported. */
function assertSingleGitDirectory(repositoryRoot) {
  const directory = gitDirectory(repositoryRoot)
  const common = gitCommonDirectory(repositoryRoot)
  if (directory !== common || fs.existsSync(path.join(directory, 'commondir'))) {
    throw new Error('exact release verification rejects split Git common directories and linked worktrees')
  }
  return directory
}

function assertNoHistorySubstitution(repositoryRoot) {
  const directory = assertSingleGitDirectory(repositoryRoot)
  for (const relative of [path.join('info', 'grafts'), 'shallow']) {
    if (fs.existsSync(path.join(directory, relative))) {
      throw new Error(`exact release verification rejects Git history substitution through ${relative}`)
    }
  }
  const replacementRefs = gitObject(
    repositoryRoot,
    ['for-each-ref', '--format=%(refname)', 'refs/replace']
  ).toString('utf8').trim()
  if (replacementRefs) {
    throw new Error('exact release verification rejects replacement refs')
  }
}

function rejectAlternateObjectStores(repositoryRoot) {
  const alternateFile = path.join(assertSingleGitDirectory(repositoryRoot), 'objects', 'info', 'alternates')
  if (fs.existsSync(alternateFile)) {
    throw new Error('exact release verification rejects alternate Git object stores')
  }
}

function assertReachableObjectIntegrity(repositoryRoot, sourceCommit) {
  assertNoHistorySubstitution(repositoryRoot)
  rejectAlternateObjectStores(repositoryRoot)
  try {
    gitObject(
      repositoryRoot,
      ['fsck', '--strict', '--full', '--no-reflogs', '--no-dangling', sourceCommit],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }
    )
  } catch (_error) {
    throw new Error('reviewed Git object integrity check failed')
  }
}

function reviewedCommit(repositoryRoot, sourceCommit) {
  if (!/^[0-9a-f]{40}$/.test(sourceCommit || '')) {
    throw new Error('reviewed release source must be an exact lowercase Git commit')
  }
  const resolved = gitObject(repositoryRoot, ['rev-parse', '--verify', `${sourceCommit}^{commit}`], {
    encoding: 'utf8'
  }).trim()
  if (resolved !== sourceCommit) {
    throw new Error('reviewed release source does not resolve to the named exact commit')
  }
  return resolved
}

function commitEntries(repositoryRoot, sourceCommit) {
  const output = gitObject(
    repositoryRoot,
    ['ls-tree', '-r', '-z', '--full-tree', sourceCommit]
  ).toString('utf8')
  const entries = []
  const seen = new Set()
  for (const record of output.split('\0').filter(Boolean)) {
    const separator = record.indexOf('\t')
    if (separator < 0) throw new Error('Git returned malformed reviewed-tree data')
    const [mode, type, objectId] = record.slice(0, separator).split(' ')
    const file = record.slice(separator + 1)
    if (
      !file ||
      file.includes('\\') ||
      file.startsWith('/') ||
      /^[A-Za-z]:/.test(file) ||
      path.posix.normalize(file) !== file ||
      file.split('/').some((segment) => segment === '' || segment === '.' || segment === '..')
    ) {
      throw new Error(`reviewed Git tree contains an unsafe path: ${file}`)
    }
    if (seen.has(file)) throw new Error(`reviewed Git tree contains a duplicate path: ${file}`)
    seen.add(file)
    if (!/^[0-9a-f]{40,64}$/.test(objectId || '')) {
      throw new Error(`Git returned an invalid reviewed object ID for ${file}`)
    }
    entries.push({ file, mode, objectId, type })
  }
  return entries
}

function readCommitBlobs(repositoryRoot, entries) {
  if (entries.length === 0) return []
  const request = `${entries.map(({ objectId }) => objectId).join('\n')}\n`
  const checked = gitObject(
    repositoryRoot,
    ['cat-file', '--batch-check=%(objectname) %(objecttype) %(objectsize)'],
    { input: request, encoding: 'utf8' }
  ).trimEnd().split('\n')
  if (checked.length !== entries.length) throw new Error('Git returned incomplete blob sizes')
  const sizedEntries = entries.map((entry, index) => {
    const [objectId, type, sizeText] = checked[index].split(' ')
    const size = Number(sizeText)
    if (
      objectId !== entry.objectId ||
      type !== 'blob' ||
      !Number.isSafeInteger(size) ||
      size < 0
    ) {
      throw new Error(`Git returned malformed blob data for ${entry.file}`)
    }
    return { ...entry, size }
  })
  const batches = []
  let current = []
  let currentBytes = 0
  const batchLimit = Math.floor(GIT_OUTPUT_MAX_BYTES / 2)
  for (const entry of sizedEntries) {
    if (entry.size > batchLimit) {
      throw new Error(`reviewed Git blob exceeds the bounded materialization size: ${entry.file}`)
    }
    if (current.length > 0 && currentBytes + entry.size > batchLimit) {
      batches.push(current)
      current = []
      currentBytes = 0
    }
    current.push(entry)
    currentBytes += entry.size
  }
  if (current.length > 0) batches.push(current)

  const blobs = []
  for (const batch of batches) {
    const output = gitObject(repositoryRoot, ['cat-file', '--batch'], {
      input: `${batch.map(({ objectId }) => objectId).join('\n')}\n`
    })
    let offset = 0
    for (const entry of batch) {
      const headerEnd = output.indexOf(0x0a, offset)
      if (headerEnd < 0) throw new Error(`Git returned truncated blob data for ${entry.file}`)
      const [objectId, type, sizeText] = output.subarray(offset, headerEnd).toString('utf8').split(' ')
      const size = Number(sizeText)
      if (objectId !== entry.objectId || type !== 'blob' || size !== entry.size) {
        throw new Error(`Git returned inconsistent blob data for ${entry.file}`)
      }
      const contentStart = headerEnd + 1
      const contentEnd = contentStart + size
      if (contentEnd >= output.length || output[contentEnd] !== 0x0a) {
        throw new Error(`Git returned truncated blob bytes for ${entry.file}`)
      }
      const bytes = output.subarray(contentStart, contentEnd)
      const actualObjectId = crypto
        .createHash('sha1')
        .update(`blob ${bytes.length}\0`)
        .update(bytes)
        .digest('hex')
      if (actualObjectId !== entry.objectId) {
        throw new Error(`reviewed Git object identity does not match its bytes: ${entry.file}`)
      }
      blobs.push(bytes)
      offset = contentEnd + 1
    }
    if (offset !== output.length) throw new Error('Git returned unexpected trailing blob data')
  }
  return blobs
}

function materializeCommit(repositoryRoot, sourceCommit, sourceRoot) {
  assertReachableObjectIntegrity(repositoryRoot, sourceCommit)
  const entries = commitEntries(repositoryRoot, sourceCommit)
  const blobs = readCommitBlobs(repositoryRoot, entries)
  for (let index = 0; index < entries.length; index += 1) {
    const { file, mode, type } = entries[index]
    if (type !== 'blob' || (mode !== '100644' && mode !== '100755')) {
      throw new Error(`reviewed source entry must be a regular Git blob: ${file}`)
    }
    const target = path.join(sourceRoot, ...file.split('/'))
    fs.mkdirSync(path.dirname(target), { recursive: true })
    fs.writeFileSync(target, blobs[index])
    fs.chmodSync(target, mode === '100755' ? 0o755 : 0o644)
  }
}

/**
 * Why
 * An exact initial checkout can be changed later while `assume-unchanged`, `skip-worktree`, filters,
 * or line-ending rules still make ordinary Git status look clean.
 *
 * What
 * Prove that every tracked file about to authorize a release is still the literal blob and mode in
 * the named commit.
 *
 * How
 * Re-read blobs through the replacement-free object path and compare them with regular worktree
 * files. Untracked tool installations such as `node_modules` are outside this commit-byte proof.
 */
function assertMaterializedCommit(repositoryRoot, sourceCommit) {
  const commit = reviewedCommit(repositoryRoot, sourceCommit)
  assertReachableObjectIntegrity(repositoryRoot, commit)
  const entries = commitEntries(repositoryRoot, commit)
  const blobs = readCommitBlobs(repositoryRoot, entries)
  for (let index = 0; index < entries.length; index += 1) {
    const { file, mode, type } = entries[index]
    if (type !== 'blob' || (mode !== '100644' && mode !== '100755')) {
      throw new Error(`reviewed source entry must be a regular Git blob: ${file}`)
    }
    const target = path.join(repositoryRoot, ...file.split('/'))
    let stat
    try {
      stat = fs.lstatSync(target)
    } catch (_error) {
      throw new Error(`reviewed source file is missing from the exact worktree: ${file}`)
    }
    if (!stat.isFile() || !fs.readFileSync(target).equals(blobs[index])) {
      throw new Error(`reviewed source file differs from the named Git blob: ${file}`)
    }
    if (process.platform !== 'win32') {
      const executable = (stat.mode & 0o111) !== 0
      if (executable !== (mode === '100755')) {
        throw new Error(`reviewed source file mode differs from the named Git mode: ${file}`)
      }
    }
  }
  return commit
}

function assertIndexMatchesCommit(repositoryRoot, sourceCommit) {
  const expected = commitEntries(repositoryRoot, sourceCommit)
    .map(({ file, mode, objectId }) => `${mode} ${objectId} 0\t${file}`)
    .sort()
  const actual = gitObject(repositoryRoot, ['ls-files', '--stage', '-z'])
    .toString('utf8')
    .split('\0')
    .filter(Boolean)
    .sort()
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error('exact release Git index does not match the reviewed commit')
  }
}

function reviewedOriginUrl(value) {
  if (!/^https:\/\/[A-Za-z0-9.-]+(?::[0-9]+)?\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\.git$/.test(value || '')) {
    throw new Error('exact release origin must be a normalized HTTPS repository URL')
  }
  return value
}

function normalizeTagSnapshot(value) {
  const records = Array.isArray(value)
    ? value
    : String(value || '').split(/\r?\n/).filter(Boolean)
  const seen = new Set()
  const normalized = records.map((record) => {
    const match = /^([0-9a-f]{40,64})\s+(refs\/tags\/[^\s]+)$/.exec(String(record).trim())
    if (!match || match[2].includes('\\') || match[2].split('/').some((part) => part === '.' || part === '..')) {
      throw new Error('authoritative Git tag snapshot contains malformed data')
    }
    const line = `${match[1]}\t${match[2]}`
    if (seen.has(match[2])) throw new Error(`authoritative Git tag snapshot repeats ${match[2]}`)
    seen.add(match[2])
    return line
  }).sort()
  return normalized
}

function localTagSnapshot(repositoryRoot) {
  const output = gitObject(
    repositoryRoot,
    ['for-each-ref', '--format=%(objectname)%09%(refname)%09%(*objectname)', 'refs/tags']
  ).toString('utf8')
  const records = []
  for (const line of output.split(/\r?\n/).filter(Boolean)) {
    const [objectId, ref, peeled = ''] = line.split('\t')
    records.push(`${objectId}\t${ref}`)
    if (peeled) records.push(`${peeled}\t${ref}^{}`)
  }
  return normalizeTagSnapshot(records)
}

function authoritativeTagSnapshot(repositoryRoot, options = {}) {
  if (Object.prototype.hasOwnProperty.call(options, 'authoritativeTags')) {
    return normalizeTagSnapshot(options.authoritativeTags)
  }
  return normalizeTagSnapshot(
    gitObject(repositoryRoot, ['ls-remote', '--tags', 'origin']).toString('utf8')
  )
}

function tagSnapshotSha256(snapshot) {
  return crypto.createHash('sha256').update(`${snapshot.join('\n')}\n`).digest('hex')
}

function synchronizeAuthoritativeTags(repositoryRoot, options = {}) {
  if (!Object.prototype.hasOwnProperty.call(options, 'authoritativeTags')) {
    gitObject(repositoryRoot, [
      'fetch',
      '--force',
      '--prune',
      '--prune-tags',
      'origin',
      '+refs/tags/*:refs/tags/*'
    ])
  }
  const authoritative = authoritativeTagSnapshot(repositoryRoot, options)
  const currentRefs = gitObject(
    repositoryRoot,
    ['for-each-ref', '--format=%(refname)', 'refs/tags']
  ).toString('utf8').split(/\r?\n/).filter(Boolean)
  for (const ref of currentRefs) gitObject(repositoryRoot, ['update-ref', '-d', ref])
  for (const record of authoritative) {
    const [objectId, ref] = record.split('\t')
    if (ref.endsWith('^{}')) continue
    gitObject(repositoryRoot, ['cat-file', '-e', `${objectId}^{object}`])
    gitObject(repositoryRoot, ['update-ref', ref, objectId])
  }
  if (JSON.stringify(localTagSnapshot(repositoryRoot)) !== JSON.stringify(authoritative)) {
    throw new Error('local Git tags do not match the authoritative remote tag snapshot')
  }
  return authoritative
}

function assertAuthoritativeTags(repositoryRoot, sourceCommit, receipt, options = {}) {
  if (
    !Array.isArray(receipt.tagSnapshot) ||
    receipt.tagSnapshotSha256 !== tagSnapshotSha256(normalizeTagSnapshot(receipt.tagSnapshot))
  ) {
    throw new Error('exact release bootstrap tag receipt is invalid')
  }
  const expected = [...normalizeTagSnapshot(receipt.tagSnapshot)]
  if (options.allowedNewTag !== undefined) {
    const tag = options.allowedNewTag
    if (!/^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(tag || '')) {
      throw new Error('allowed release tag must use exact stable semantic-version syntax')
    }
    const ref = `refs/tags/${tag}`
    if (expected.some((record) => record.endsWith(`\t${ref}`) || record.endsWith(`\t${ref}^{}`))) {
      throw new Error('new release tag already existed in the bootstrap tag snapshot')
    }
    expected.push(`${sourceCommit}\t${ref}`)
    expected.sort()
  }
  const authoritative = authoritativeTagSnapshot(repositoryRoot, options)
  const local = localTagSnapshot(repositoryRoot)
  if (JSON.stringify(authoritative) !== JSON.stringify(expected) || JSON.stringify(local) !== JSON.stringify(expected)) {
    throw new Error('local Git tag namespace differs from the authoritative remote tag snapshot')
  }
}

function reviewedLocalConfig(directory, originUrl) {
  const hooksDirectory = path.join(directory, 'haxe-rust-empty-hooks')
  return [
    '[core]',
    '\trepositoryformatversion = 0',
    '\tfilemode = false',
    '\tbare = false',
    '\tlogallrefupdates = true',
    `\thooksPath = ${hooksDirectory}`,
    '[remote "origin"]',
    `\turl = ${reviewedOriginUrl(originUrl)}`,
    '\tfetch = +refs/heads/*:refs/remotes/origin/*',
    ''
  ].join('\n')
}

function administrativeState(repositoryRoot, originUrl) {
  const directory = assertSingleGitDirectory(repositoryRoot)
  const hooksDirectory = path.join(directory, 'haxe-rust-empty-hooks')
  const expectedConfig = reviewedLocalConfig(directory, originUrl)
  return {
    configSha256: crypto.createHash('sha256').update(expectedConfig).digest('hex'),
    expectedConfig,
    hooksDirectory,
    originUrl: reviewedOriginUrl(originUrl)
  }
}

function assertAdministrativeState(repositoryRoot, receipt, originUrl) {
  const directory = assertSingleGitDirectory(repositoryRoot)
  const current = administrativeState(repositoryRoot, originUrl)
  const configuration = path.join(directory, 'config')
  if (
    fs.readFileSync(configuration, 'utf8') !== current.expectedConfig ||
    current.configSha256 !== receipt.configSha256 ||
    current.hooksDirectory !== receipt.hooksDirectory ||
    current.originUrl !== receipt.originUrl
  ) {
    throw new Error('exact release Git administration differs from the bootstrap receipt')
  }
  const hooksStat = fs.lstatSync(current.hooksDirectory)
  if (!hooksStat.isDirectory() || fs.readdirSync(current.hooksDirectory).length !== 0) {
    throw new Error('exact release trusted hooks directory must remain empty')
  }
  for (const relative of [
    'commondir',
    'config.worktree',
    path.join('info', 'grafts'),
    path.join('objects', 'info', 'alternates'),
    path.join('info', 'attributes'),
    'shallow'
  ]) {
    if (fs.existsSync(path.join(directory, relative))) {
      throw new Error(`exact release Git administration contains unsupported ${relative}`)
    }
  }
}

/** Reject untracked or ignored code/config that Node or shell resolution could load pre-release. */
function assertNoPreloadShadows(repositoryRoot) {
  const candidates = []
  for (const args of [
    ['ls-files', '-z', '--others', '--exclude-standard'],
    ['ls-files', '-z', '--others', '--ignored', '--exclude-standard']
  ]) {
    candidates.push(
      ...gitObject(repositoryRoot, [...args, '--', ...PRELOAD_PROTECTED_PATHS])
        .toString('utf8')
        .split('\0')
        .filter(Boolean)
    )
  }
  const shadows = [...new Set(candidates)].sort()
  if (shadows.length > 0) {
    throw new Error(`unreviewed code or configuration could load before release: ${shadows.join(', ')}`)
  }
}

function bootstrapRepository(repositoryRoot, sourceCommit, destination, originUrl, options = {}) {
  const commit = reviewedCommit(repositoryRoot, sourceCommit)
  const reviewedOrigin = reviewedOriginUrl(originUrl)
  assertReachableObjectIntegrity(repositoryRoot, commit)
  if (fs.existsSync(destination)) throw new Error('exact release destination already exists')
  gitObject(repositoryRoot, ['clone', '--no-checkout', '--no-hardlinks', '--no-local', repositoryRoot, destination])
  const clonedCommit = reviewedCommit(destination, commit)
  gitObject(destination, ['read-tree', '--reset', clonedCommit])
  materializeCommit(destination, clonedCommit, destination)
  gitObject(destination, ['update-ref', 'HEAD', clonedCommit])
  const exactGitDirectory = assertSingleGitDirectory(destination)
  const hooksDirectory = path.join(exactGitDirectory, 'haxe-rust-empty-hooks')
  fs.mkdirSync(hooksDirectory, { mode: 0o700 })
  fs.writeFileSync(
    path.join(exactGitDirectory, 'config'),
    reviewedLocalConfig(exactGitDirectory, reviewedOrigin),
    { mode: 0o600 }
  )
  const tagSnapshot = synchronizeAuthoritativeTags(destination, options)
  const status = gitObject(destination, ['status', '--porcelain', '--untracked-files=no'], {
    encoding: 'utf8'
  })
  if (status.trim().length > 0) throw new Error('exact release source does not match its Git index')
  assertIndexMatchesCommit(destination, clonedCommit)
  const bootstrapEntry = commitEntries(destination, clonedCommit).find(
    ({ file }) => file === 'scripts/release/exact-git-source.js'
  )
  if (!bootstrapEntry) throw new Error('reviewed release source lacks its exact-object bootstrap')
  const state = administrativeState(destination, reviewedOrigin)
  fs.writeFileSync(
    path.join(exactGitDirectory, BOOTSTRAP_RECEIPT),
    `${JSON.stringify({
      schemaVersion: 3,
      sourceCommit: clonedCommit,
      bootstrapObjectId: bootstrapEntry.objectId,
      configSha256: state.configSha256,
      hooksDirectory: state.hooksDirectory,
      originUrl: state.originUrl,
      tagSnapshot,
      tagSnapshotSha256: tagSnapshotSha256(tagSnapshot)
    })}\n`,
    { mode: 0o600 }
  )
  return destination
}

function assertExactBootstrap(
  repositoryRoot,
  sourceCommit,
  originUrl = process.env.RELEASE_EXPECTED_ORIGIN_URL,
  options = {}
) {
  const commit = reviewedCommit(repositoryRoot, sourceCommit)
  const reviewedOrigin = reviewedOriginUrl(originUrl)
  const receiptPath = path.join(assertSingleGitDirectory(repositoryRoot), BOOTSTRAP_RECEIPT)
  if (!fs.existsSync(receiptPath)) {
    throw new Error('release authority must run from the externally bootstrapped exact Git object')
  }
  let receipt
  try {
    receipt = JSON.parse(fs.readFileSync(receiptPath, 'utf8'))
  } catch (_error) {
    throw new Error('exact release bootstrap receipt is invalid')
  }
  const bootstrapEntry = commitEntries(repositoryRoot, commit).find(
    ({ file }) => file === 'scripts/release/exact-git-source.js'
  )
  if (
    receipt.schemaVersion !== 3 ||
    receipt.sourceCommit !== commit ||
    receipt.bootstrapObjectId !== bootstrapEntry?.objectId
  ) {
    throw new Error('exact release bootstrap receipt does not match the reviewed commit')
  }
  assertAdministrativeState(repositoryRoot, receipt, reviewedOrigin)
  assertNoHistorySubstitution(repositoryRoot)
  assertAuthoritativeTags(repositoryRoot, commit, receipt, options)
  assertIndexMatchesCommit(repositoryRoot, commit)
  assertMaterializedCommit(repositoryRoot, commit)
  assertNoPreloadShadows(repositoryRoot)
  return commit
}

function main() {
  const [command, repositoryRoot, sourceCommit, destinationOrOrigin, originUrl, ...rest] = process.argv.slice(2)
  if (command === 'assert' && repositoryRoot && sourceCommit && destinationOrOrigin && originUrl === undefined && rest.length === 0) {
    assertExactBootstrap(path.resolve(repositoryRoot), sourceCommit, destinationOrOrigin)
    console.log('[exact-git-source] exact reviewed release repository verified')
    return
  }
  if (command !== 'bootstrap' || !repositoryRoot || !sourceCommit || !destinationOrOrigin || !originUrl || rest.length > 0) {
    throw new Error(
      'usage: exact-git-source.js bootstrap <repository> <commit> <destination> <origin-url> | assert <repository> <commit> <origin-url>'
    )
  }
  bootstrapRepository(path.resolve(repositoryRoot), sourceCommit, path.resolve(destinationOrOrigin), originUrl)
  console.log('[exact-git-source] materialized reviewed release repository')
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[exact-git-source] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = {
  GIT_OUTPUT_MAX_BYTES,
  assertAuthoritativeTags,
  assertExactBootstrap,
  assertIndexMatchesCommit,
  assertMaterializedCommit,
  assertNoPreloadShadows,
  assertSingleGitDirectory,
  authoritativeTagSnapshot,
  bootstrapRepository,
  commitEntries,
  gitObject,
  gitBinary,
  gitCommonDirectory,
  gitObjectEnvironment,
  localTagSnapshot,
  materializeCommit,
  reviewedCommit
}
