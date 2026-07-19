#!/usr/bin/env node

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')

const repoRoot = path.resolve(__dirname, '..', '..')
const pluginPath = path.join(repoRoot, 'test', 'fixtures', 'release-lifecycle-plugin.cjs')

function git(args, cwd, allowFailure = false) {
  try {
    return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()
  } catch (error) {
    if (allowFailure) return null
    throw error
  }
}

function write(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, content)
}

function tagState(tag, cwd) {
  return {
    local: git(['show-ref', '--verify', `refs/tags/${tag}`], cwd, true),
    remote: git(['ls-remote', '--exit-code', '--tags', 'origin', `refs/tags/${tag}`], cwd, true)
  }
}

async function expectReject(promise, pattern) {
  try {
    await promise
    assert.fail('expected semantic-release to reject')
  } catch (error) {
    assert.match(error.stack || error.message, pattern)
  }
}

/**
 * Keep this isolated release repository independent from the outer CI checkout.
 *
 * semantic-release asks env-ci for the current branch. Forwarding GitHub Actions
 * identity would make the temporary repository look like the caller's feature
 * branch or pull-request merge ref even though its own checked-out branch is
 * deliberately `main`.
 */
function isolatedReleaseEnvironment(statePath) {
  const env = { ...process.env }
  delete env.GITHUB_ACTIONS
  return {
    ...env,
    RELEASE_LIFECYCLE_STATE: statePath
  }
}

async function main() {
  const { default: semanticRelease } = await import('semantic-release')
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-release-lifecycle-'))
  const remote = path.join(temp, 'remote.git')
  const work = path.join(temp, 'work')
  const statePath = path.join(temp, 'state.json')
  try {
    fs.mkdirSync(work)
    git(['init', '--bare', remote], temp)
    git(['init', '-b', 'main'], work)
    git(['config', 'user.name', 'Release Lifecycle Test'], work)
    git(['config', 'user.email', 'release-lifecycle@example.invalid'], work)
    git(['remote', 'add', 'origin', remote], work)

    write(path.join(work, 'fixture.txt'), 'baseline\n')
    git(['add', 'fixture.txt'], work)
    git(['commit', '-m', 'chore: seed release lineage'], work)
    git(['tag', 'v0.1.0'], work)
    git(['push', '--set-upstream', 'origin', 'main'], work)
    git(['push', 'origin', 'v0.1.0'], work)
    git(['symbolic-ref', 'HEAD', 'refs/heads/main'], remote)

    write(path.join(work, 'fixture.txt'), 'candidate\n')
    git(['add', 'fixture.txt'], work)
    git(['commit', '-m', 'fix: exercise release lifecycle'], work)
    git(['push', 'origin', 'main'], work)
    const candidate = git(['rev-parse', 'HEAD^{commit}'], work)

    const options = {
      branches: ['main'],
      ci: false,
      plugins: [pluginPath],
      repositoryUrl: remote,
      tagFormat: 'v${version}'
    }
    const baseEnvironment = isolatedReleaseEnvironment(statePath)

    await expectReject(
      semanticRelease(options, {
        cwd: work,
        env: { ...baseEnvironment, RELEASE_LIFECYCLE_FAIL_PREPARE: '1' }
      }),
      /injected deterministic preparation failure/
    )
    assert.deepStrictEqual(tagState('v0.1.1', work), { local: null, remote: null })
    assert.strictEqual(git(['rev-parse', 'refs/heads/main'], remote), candidate)
    const failedState = JSON.parse(fs.readFileSync(statePath, 'utf8'))
    assert.deepStrictEqual(failedState.prepare, {
      head: candidate,
      localTag: false,
      remoteTag: false,
      tag: 'v0.1.1',
      version: '0.1.1'
    })

    fs.rmSync(statePath, { force: true })
    const result = await semanticRelease(options, {
      cwd: work,
      env: { ...baseEnvironment, RELEASE_LIFECYCLE_FAIL_PREPARE: '0' }
    })
    assert.strictEqual(result.nextRelease.version, '0.1.1')
    assert.strictEqual(git(['rev-parse', 'refs/tags/v0.1.1^{commit}'], work), candidate)
    assert.match(tagState('v0.1.1', work).remote, new RegExp(`^${candidate}\\s+refs/tags/v0\\.1\\.1$`))
    const successState = JSON.parse(fs.readFileSync(statePath, 'utf8'))
    assert.deepStrictEqual(successState.prepare, {
      head: candidate,
      localTag: false,
      remoteTag: false,
      tag: 'v0.1.1',
      version: '0.1.1'
    })
    assert.deepStrictEqual(successState.publish, {
      head: candidate,
      localTag: true,
      remoteTag: true,
      tag: 'v0.1.1',
      version: '0.1.1'
    })

    console.log('[release-lifecycle-test] OK')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

main().catch((error) => {
  console.error(error.stack || error.message)
  process.exit(1)
})
