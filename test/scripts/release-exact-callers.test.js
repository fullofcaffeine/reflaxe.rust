#!/usr/bin/env node

const assert = require('assert')
const crypto = require('crypto')
const { execFileSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const TEST_ORIGIN = 'https://example.invalid/example/repository.git'

function git(cwd, args, options = {}) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', ...options })
}

function writeExecutable(file, source) {
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, source)
  fs.chmodSync(file, 0o755)
}

function copyReviewedReleaseFiles(destination) {
  for (const relative of [
    'scripts/release/exact-git-source.js',
    'scripts/release/haxelib-artifact-plugin.cjs',
    'scripts/release/package-input-cleanliness.js',
    'scripts/release/published-verifier-plugin.cjs',
    'scripts/release/release-policy.js',
    'scripts/release/release-provenance.js',
    'scripts/release/repair-release.js',
    'scripts/release/reviewed-source.js',
    'scripts/release/semantic-version.js'
  ]) {
    const target = path.join(destination, relative)
    fs.mkdirSync(path.dirname(target), { recursive: true })
    fs.copyFileSync(path.join(repoRoot, relative), target)
  }
}

function context(cwd) {
  return {
    cwd,
    nextRelease: { version: '1.2.3', gitTag: 'v1.2.3', notes: 'Fixture release notes' },
    logger: { success() {} }
  }
}

async function main() {
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-real-release-callers-'))
  const repository = path.join(temporaryRoot, 'repository')
  const exactRoot = path.join(temporaryRoot, 'exact-source')
  const externalBootstrap = path.join(temporaryRoot, 'exact-git-source.js')
  const injectedMarker = path.join(temporaryRoot, 'injected-shell-environment.txt')
  const bashEnvironment = path.join(temporaryRoot, 'bash-environment.sh')
  const originalGithubSha = process.env.GITHUB_SHA
  const originalBashEnvironment = process.env.BASH_ENV
  const originalReleaseGh = process.env.RELEASE_GH_BIN
  const originalReleaseGit = process.env.RELEASE_GIT_BIN
  const originalExpectedOrigin = process.env.RELEASE_EXPECTED_ORIGIN_URL
  const originalArgv = process.argv

  try {
    fs.mkdirSync(repository)
    git(repository, ['init', '-q'])
    git(repository, ['config', 'user.name', 'Release Caller Test'])
    git(repository, ['config', 'user.email', 'release-caller@example.invalid'])
    copyReviewedReleaseFiles(repository)
    writeExecutable(
      path.join(repository, 'scripts', 'release', 'package-haxelib.sh'),
      '#!/usr/bin/env bash\nset -euo pipefail\nmkdir -p "$(dirname "$1")"\nprintf "reviewed artifact\\n" > "$1"\n'
    )
    fs.writeFileSync(
      path.join(repository, 'scripts', 'release', 'verify-release-artifact.js'),
      `const crypto = require('crypto')
const fs = require('fs')
function verifyReleaseArtifact({ zipPath, canonicalZipPath }) {
  const bytes = fs.readFileSync(zipPath)
  if (!bytes.equals(fs.readFileSync(canonicalZipPath))) {
    throw new Error('candidate and canonical fixture artifacts differ')
  }
  return {
    entries: ['fixture'],
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
    size: bytes.length
  }
}
module.exports = { verifyReleaseArtifact }
`
    )
    writeExecutable(
      path.join(repository, 'scripts', 'ci', 'package-smoke.sh'),
      '#!/usr/bin/env bash\nset -euo pipefail\ntest "${PACKAGE_SMOKE_USE_EXISTING:-}" = "1"\ntest "$(cat "$PACKAGE_ZIP_REL")" = "reviewed artifact"\n'
    )
    fs.writeFileSync(
      path.join(repository, 'release-manifest.json'),
      `${JSON.stringify({
        schemaVersion: 2,
        releaseLines: {
          0: { stage: 'initial-development', breakingBump: 'minor' },
          1: {
            stage: 'stable',
            approval: { record: 'test/scripts/release-exact-callers.test.js', date: '2026-08-01' }
          }
        }
      }, null, 2)}\n`
    )
    git(repository, ['add', '.'])
    git(repository, ['commit', '-q', '-m', 'reviewed release caller fixture'])
    const reviewed = git(repository, ['rev-parse', 'HEAD']).trim()
    git(repository, ['tag', 'v1.2.3', reviewed])

    fs.writeFileSync(
      path.join(repository, 'scripts', 'release', 'package-haxelib.sh'),
      '#!/usr/bin/env bash\nprintf "replacement artifact\\n" > "$1"\n'
    )
    git(repository, ['add', '.'])
    git(repository, ['commit', '-q', '-m', 'replacement release caller fixture'])
    const replacement = git(repository, ['rev-parse', 'HEAD']).trim()
    git(repository, ['checkout', '-q', '--detach', reviewed])
    git(repository, ['replace', reviewed, replacement])

    for (const relative of [
      'scripts/release/exact-git-source.js',
      'scripts/release/package-haxelib.sh'
    ]) {
      git(repository, ['update-index', '--assume-unchanged', relative])
      fs.writeFileSync(path.join(repository, relative), 'throw new Error("live worktree was used")\n')
    }
    fs.mkdirSync(path.join(repository, '.git', 'info'), { recursive: true })
    fs.writeFileSync(
      path.join(repository, '.git', 'info', 'attributes'),
      'scripts/release/package-haxelib.sh export-ignore\n'
    )
    assert.strictEqual(
      git(repository, ['--no-replace-objects', 'status', '--porcelain', '--untracked-files=no']),
      '',
      'the fixture must reproduce hidden live-worktree changes'
    )

    const bootstrapBytes = execFileSync(
      'git',
      [
        '--no-replace-objects',
        'cat-file',
        'blob',
        `${reviewed}:scripts/release/exact-git-source.js`
      ],
      {
        cwd: repository,
        env: {
          PATH: process.env.PATH,
          GIT_ATTR_NOSYSTEM: '1',
          GIT_CONFIG_GLOBAL: process.platform === 'win32' ? 'NUL' : '/dev/null',
          GIT_CONFIG_NOSYSTEM: '1',
          GIT_NO_REPLACE_OBJECTS: '1'
        }
      }
    )
    fs.writeFileSync(externalBootstrap, bootstrapBytes, { mode: 0o700 })
    execFileSync(
      process.execPath,
      [externalBootstrap, 'bootstrap', repository, reviewed, exactRoot, TEST_ORIGIN],
      { stdio: 'pipe' }
    )
    assert.match(
      fs.readFileSync(path.join(exactRoot, 'scripts', 'release', 'package-haxelib.sh'), 'utf8'),
      /reviewed artifact/,
      'the externally loaded bootstrap must ignore replacement refs, attributes, and live bytes'
    )

    const exactPlugin = path.join(exactRoot, 'scripts', 'release', 'haxelib-artifact-plugin.cjs')
    const reviewedPluginBytes = fs.readFileSync(exactPlugin)
    git(exactRoot, ['update-index', '--assume-unchanged', 'scripts/release/haxelib-artifact-plugin.cjs'])
    fs.writeFileSync(exactPlugin, 'throw new Error("hidden release entrypoint")\n')
    let externalAssertRejected = false
    try {
      execFileSync(
        process.execPath,
        [externalBootstrap, 'assert', exactRoot, reviewed, TEST_ORIGIN],
        { stdio: ['ignore', 'pipe', 'pipe'] }
      )
    } catch (error) {
      externalAssertRejected = true
      assert.match(
        String(error.stderr),
        /reviewed source file differs from the named Git blob: scripts\/release\/haxelib-artifact-plugin\.cjs/
      )
    }
    assert(externalAssertRejected, 'the external pre-load check must reject a hidden entrypoint edit')
    fs.writeFileSync(exactPlugin, reviewedPluginBytes)
    git(exactRoot, ['update-index', '--no-assume-unchanged', 'scripts/release/haxelib-artifact-plugin.cjs'])
    const shadowModule = path.join(
      exactRoot,
      'scripts',
      'release',
      'node_modules',
      '@semantic-release',
      'commit-analyzer',
      'index.js'
    )
    fs.mkdirSync(path.dirname(shadowModule), { recursive: true })
    fs.writeFileSync(shadowModule, 'module.exports = { analyzeCommits: async () => "major" }\n')
    let shadowRejected = false
    try {
      execFileSync(
        process.execPath,
        [externalBootstrap, 'assert', exactRoot, reviewed, TEST_ORIGIN],
        { stdio: ['ignore', 'pipe', 'pipe'] }
      )
    } catch (error) {
      shadowRejected = true
      assert.match(String(error.stderr), /unreviewed code or configuration could load before release/)
    }
    assert(shadowRejected, 'the external pre-load check must reject a nested dependency shadow')
    fs.rmSync(path.join(exactRoot, 'scripts', 'release', 'node_modules'), {
      recursive: true,
      force: true
    })
    execFileSync(
      process.execPath,
      [externalBootstrap, 'assert', exactRoot, reviewed, TEST_ORIGIN],
      { stdio: 'pipe' }
    )

    const fakeGit = path.join(temporaryRoot, 'git')
    writeExecutable(
      fakeGit,
      `#!${process.execPath}
const { spawnSync } = require('child_process')
const args = process.argv.slice(2)
if (args[0] === '--no-replace-objects') args.shift()
if (args[0] === 'ls-remote') {
  process.stdout.write(${JSON.stringify(`${reviewed}\trefs/tags/v1.2.3\n`)})
  process.exit(0)
}
const result = spawnSync('/usr/bin/git', ['--no-replace-objects', ...args], { stdio: 'inherit' })
process.exit(result.status === null ? 1 : result.status)
`
    )
    process.env.GITHUB_SHA = reviewed
    process.env.RELEASE_EXPECTED_ORIGIN_URL = TEST_ORIGIN
    process.env.RELEASE_GIT_BIN = fakeGit
    fs.writeFileSync(bashEnvironment, `printf injected > "${injectedMarker}"\n`)
    process.env.BASH_ENV = bashEnvironment
    const plugin = require(path.join(exactRoot, 'scripts', 'release', 'haxelib-artifact-plugin.cjs'))

    const exactPackageScript = path.join(exactRoot, 'scripts', 'release', 'package-haxelib.sh')
    const reviewedPackageBytes = fs.readFileSync(exactPackageScript)
    git(exactRoot, ['update-index', '--assume-unchanged', 'scripts/release/package-haxelib.sh'])
    fs.writeFileSync(exactPackageScript, '#!/usr/bin/env bash\nprintf hidden > "$1"\n')
    await assert.rejects(
      () => plugin.prepare({}, context(exactRoot)),
      /reviewed source file differs from the named Git blob: scripts\/release\/package-haxelib\.sh/,
      'the real prepare caller must reject a post-bootstrap hidden worktree substitution'
    )
    fs.writeFileSync(exactPackageScript, reviewedPackageBytes)
    fs.chmodSync(exactPackageScript, 0o755)
    git(exactRoot, ['update-index', '--no-assume-unchanged', 'scripts/release/package-haxelib.sh'])

    await plugin.prepare({}, context(exactRoot))
    assert.strictEqual(
      fs.readFileSync(path.join(exactRoot, 'dist', 'reflaxe.rust.zip'), 'utf8'),
      'reviewed artifact\n',
      'the real prepare caller must package only reviewed bytes'
    )
    assert(!fs.existsSync(injectedMarker), 'release shell children must not load caller BASH_ENV')
    await plugin.publish({}, context(exactRoot))
    assert(!fs.existsSync(injectedMarker), 'publication rebuilds must retain the sanitized environment')
    const approvedZip = fs.readFileSync(path.join(exactRoot, 'dist', 'reflaxe.rust.zip'))
    const approvedChecksum = fs.readFileSync(path.join(exactRoot, 'dist', 'reflaxe.rust.zip.sha256'))
    const fakeGhState = path.join(temporaryRoot, 'fake-gh-state.json')
    const fakeGh = path.join(temporaryRoot, 'gh')
    writeExecutable(
      fakeGh,
      `#!${process.execPath}
const crypto = require('crypto')
const fs = require('fs')
const statePath = ${JSON.stringify(fakeGhState)}
const args = process.argv.slice(2)
const read = () => fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : null
const write = (state) => fs.writeFileSync(statePath, JSON.stringify(state))
const identity = (file) => {
  const bytes = fs.readFileSync(file)
  return { size: bytes.length, digest: 'sha256:' + crypto.createHash('sha256').update(bytes).digest('hex') }
}
if (args[0] !== 'release') process.exit(3)
if (args[1] === 'view') {
  const state = read()
  if (!state) process.exit(1)
  process.stdout.write(JSON.stringify(state))
} else if (args[1] === 'create') {
  write({ tagName: args[2], isDraft: true, isImmutable: false, isPrerelease: false, assets: [] })
} else if (args[1] === 'upload') {
  const state = read()
  for (const argument of args.slice(3)) {
    if (argument.startsWith('--')) continue
    const file = argument.split('#', 1)[0]
    const measured = identity(file)
    state.assets.push({ name: require('path').basename(file), state: 'uploaded', ...measured })
  }
  write(state)
} else if (args[1] === 'edit') {
  const state = read()
  state.isDraft = false
  state.isImmutable = true
  write(state)
} else {
  process.exit(4)
}
`
    )
    process.env.RELEASE_GH_BIN = fakeGh
    const publisher = require(path.join(exactRoot, 'scripts', 'release', 'published-verifier-plugin.cjs'))
    fs.writeFileSync(path.join(exactRoot, 'dist', 'reflaxe.rust.zip'), 'mutated after approval\n')
    await assert.rejects(
      () => publisher.publish({}, context(exactRoot)),
      /changed after approval/,
      'the real hosted publisher must consume the captured approval rather than mutable dist bytes'
    )
    assert(!fs.existsSync(fakeGhState), 'a receipt mismatch must fail before creating a GitHub Release')

    const receiptPath = path.resolve(
      exactRoot,
      git(exactRoot, ['rev-parse', '--git-dir']).trim(),
      'haxe-rust-approved-artifact.json'
    )
    assert(!fs.existsSync(receiptPath), 'approval identity must not be written to mutable repository storage')
    const substitutedZip = Buffer.from('coherently substituted after approval\n')
    const substitutedChecksumText = `${crypto.createHash('sha256').update(substitutedZip).digest('hex')}  reflaxe.rust-1.2.3.zip\n`
    const substitutedChecksum = Buffer.from(substitutedChecksumText)
    const substitutedReceipt = {
      schemaVersion: 1,
      version: '1.2.3',
      tag: 'v1.2.3',
      sourceCommit: reviewed,
      archive: {
        name: 'reflaxe.rust-1.2.3.zip',
        digest: `sha256:${crypto.createHash('sha256').update(substitutedZip).digest('hex')}`,
        size: substitutedZip.length
      },
      checksum: {
        name: 'reflaxe.rust-1.2.3.zip.sha256',
        digest: `sha256:${crypto.createHash('sha256').update(substitutedChecksum).digest('hex')}`,
        size: substitutedChecksum.length
      },
      checksumText: substitutedChecksumText
    }
    fs.writeFileSync(path.join(exactRoot, 'dist', 'reflaxe.rust.zip'), substitutedZip)
    fs.writeFileSync(path.join(exactRoot, 'dist', 'reflaxe.rust.zip.sha256'), substitutedChecksum)
    fs.writeFileSync(receiptPath, `${JSON.stringify(substitutedReceipt)}\n`)
    await assert.rejects(
      () => publisher.publish({}, context(exactRoot)),
      /changed after approval|captured approval.*replace|replace.*captured approval/,
      'mutable files must not be able to replace the in-process approval identity'
    )
    assert(!fs.existsSync(fakeGhState), 'a substituted approval must fail before creating a GitHub Release')

    fs.rmSync(receiptPath, { force: true })
    fs.writeFileSync(path.join(exactRoot, 'dist', 'reflaxe.rust.zip'), approvedZip)
    fs.writeFileSync(path.join(exactRoot, 'dist', 'reflaxe.rust.zip.sha256'), approvedChecksum)
    await publisher.publish({}, context(exactRoot))
    const hosted = JSON.parse(fs.readFileSync(fakeGhState, 'utf8'))
    assert(hosted.isImmutable, 'the source-owned publisher must make the verified release immutable')
    assert.deepStrictEqual(
      hosted.assets.map(({ name }) => name).sort(),
      ['reflaxe.rust-1.2.3.zip', 'reflaxe.rust-1.2.3.zip.sha256'],
      'the source-owned publisher must upload exactly the two receipt-bound assets'
    )
    const repair = require(path.join(exactRoot, 'scripts', 'release', 'repair-release.js'))
    const repaired = repair.buildApprovedArtifact({
      cwd: exactRoot,
      version: '1.2.3',
      tag: 'v1.2.3',
      sourceCommit: reviewed
    })
    assert.strictEqual(
      fs.readFileSync(repaired.zipPath, 'utf8'),
      'reviewed artifact\n',
      'the real repair artifact builder must package only reviewed bytes'
    )
    assert(!fs.existsSync(injectedMarker), 'repair rebuilds must retain the sanitized environment')
    fs.rmSync(fakeGhState, { force: true })
    process.argv = [process.execPath, path.join(exactRoot, 'scripts', 'release', 'repair-release.js'), 'v1.2.3']
    repair.main()
    const repairedHosted = JSON.parse(fs.readFileSync(fakeGhState, 'utf8'))
    assert(repairedHosted.isImmutable, 'the real repair caller must publish only receipt-bound assets')
    assert.deepStrictEqual(
      repairedHosted.assets.map(({ name }) => name).sort(),
      ['reflaxe.rust-1.2.3.zip', 'reflaxe.rust-1.2.3.zip.sha256'],
      'repair must upload exactly the approved archive and checksum'
    )

    console.log('[release-exact-callers-test] OK')
  } finally {
    if (originalGithubSha === undefined) delete process.env.GITHUB_SHA
    else process.env.GITHUB_SHA = originalGithubSha
    if (originalBashEnvironment === undefined) delete process.env.BASH_ENV
    else process.env.BASH_ENV = originalBashEnvironment
    if (originalReleaseGh === undefined) delete process.env.RELEASE_GH_BIN
    else process.env.RELEASE_GH_BIN = originalReleaseGh
    if (originalReleaseGit === undefined) delete process.env.RELEASE_GIT_BIN
    else process.env.RELEASE_GIT_BIN = originalReleaseGit
    if (originalExpectedOrigin === undefined) delete process.env.RELEASE_EXPECTED_ORIGIN_URL
    else process.env.RELEASE_EXPECTED_ORIGIN_URL = originalExpectedOrigin
    process.argv = originalArgv
    fs.rmSync(temporaryRoot, { recursive: true, force: true })
  }
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
