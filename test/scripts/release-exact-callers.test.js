#!/usr/bin/env node

const assert = require('assert')
const { execFileSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')

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
    nextRelease: { version: '1.2.3', gitTag: 'v1.2.3' },
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
      [externalBootstrap, 'bootstrap', repository, reviewed, exactRoot],
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
        [externalBootstrap, 'assert', exactRoot, reviewed],
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
        [externalBootstrap, 'assert', exactRoot, reviewed],
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
      [externalBootstrap, 'assert', exactRoot, reviewed],
      { stdio: 'pipe' }
    )

    process.env.GITHUB_SHA = reviewed
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

    console.log('[release-exact-callers-test] OK')
  } finally {
    if (originalGithubSha === undefined) delete process.env.GITHUB_SHA
    else process.env.GITHUB_SHA = originalGithubSha
    if (originalBashEnvironment === undefined) delete process.env.BASH_ENV
    else process.env.BASH_ENV = originalBashEnvironment
    fs.rmSync(temporaryRoot, { recursive: true, force: true })
  }
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
