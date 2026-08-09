#!/usr/bin/env node

const assert = require('assert')
const { execFileSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
const zlib = require('zlib')
const {
  assertExactBootstrap,
  bootstrapRepository,
  materializeCommit
} = require('../../scripts/release/exact-git-source.js')

const repoRoot = path.resolve(__dirname, '..', '..')
const TEST_ORIGIN = 'https://example.invalid/example/repository.git'
const FIXTURE_TAGS = { authoritativeTags: [] }

function git(cwd, args, options = {}) {
  return execFileSync('git', args, {
    cwd,
    encoding: options.encoding || 'utf8',
    input: options.input,
    maxBuffer: 8 * 1024 * 1024
  })
}

function commitFixture(root) {
  git(root, ['init', '-q'])
  fs.mkdirSync(path.join(root, 'scripts', 'release'), { recursive: true })
  fs.copyFileSync(
    path.join(repoRoot, 'scripts', 'release', 'exact-git-source.js'),
    path.join(root, 'scripts', 'release', 'exact-git-source.js')
  )
  fs.mkdirSync(path.join(root, 'src'), { recursive: true })
  fs.writeFileSync(path.join(root, 'src', 'Payload.hx'), 'reviewed payload\n')
  git(root, ['add', '.'])
  git(root, [
    '-c',
    'user.name=Exact Source Test',
    '-c',
    'user.email=exact-source@example.invalid',
    'commit',
    '-q',
    '-m',
    'reviewed source'
  ])
  return git(root, ['rev-parse', 'HEAD']).trim()
}

function withBootstrap(label, operation) {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), `haxe-rust-exact-${label}-`))
  const source = path.join(fixture, 'source')
  const exact = path.join(fixture, 'exact')
  try {
    fs.mkdirSync(source)
    const commit = commitFixture(source)
    bootstrapRepository(source, commit, exact, TEST_ORIGIN, FIXTURE_TAGS)
    operation({ commit, exact, fixture, source })
  } finally {
    fs.rmSync(fixture, { recursive: true, force: true })
  }
}

function replaceLooseBlob(repositoryRoot, objectId, content) {
  const objectPath = path.join(
    repositoryRoot,
    '.git',
    'objects',
    objectId.slice(0, 2),
    objectId.slice(2)
  )
  const bytes = Buffer.from(content)
  const object = Buffer.concat([Buffer.from(`blob ${bytes.length}\0`), bytes])
  fs.chmodSync(objectPath, 0o644)
  fs.writeFileSync(objectPath, zlib.deflateSync(object))
}

function main() {
  const corrupt = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-corrupt-object-'))
  try {
    fs.mkdirSync(path.join(corrupt, 'source'))
    const source = path.join(corrupt, 'source')
    const commit = commitFixture(source)
    const payloadObject = git(source, ['rev-parse', `${commit}:src/Payload.hx`]).trim()
    replaceLooseBlob(source, payloadObject, 'attacker payload\n')
    const destination = path.join(corrupt, 'materialized')
    fs.mkdirSync(destination)
    assert.throws(
      () => materializeCommit(source, commit, destination),
      /object (identity|hash)|Git object integrity|corrupt/i,
      'literal object bytes must be hashed independently before they can authorize a release'
    )
  } finally {
    fs.rmSync(corrupt, { recursive: true, force: true })
  }

  for (const relative of [
    '.releaserc.js',
    'scripts/release/node_modules/attacker/index.js'
  ]) {
    withBootstrap('staged-shadow', ({ commit, exact }) => {
      const target = path.join(exact, relative)
      fs.mkdirSync(path.dirname(target), { recursive: true })
      fs.writeFileSync(target, 'throw new Error("unreviewed preload");\n')
      git(exact, ['add', relative])
      assert.throws(
        () => assertExactBootstrap(exact, commit, TEST_ORIGIN, FIXTURE_TAGS),
        /index.*reviewed commit|unreviewed.*(code|configuration)|staged/i,
        `${relative} must not become release authority merely by entering the live index`
      )
    })
  }

  withBootstrap('config', ({ commit, exact, fixture }) => {
    const hookRoot = path.join(fixture, 'hooks')
    fs.mkdirSync(hookRoot)
    fs.writeFileSync(path.join(hookRoot, 'pre-push'), '#!/bin/sh\nexit 0\n')
    git(exact, ['config', 'core.hooksPath', hookRoot])
    assert.throws(
      () => assertExactBootstrap(exact, commit, TEST_ORIGIN, FIXTURE_TAGS),
      /Git administration|hooks|config/i,
      'post-bootstrap Git configuration must not add an executable authority'
    )
  })

  withBootstrap('self-validating-config', ({ commit, exact }) => {
    const receiptPath = path.join(exact, '.git', 'haxe-rust-exact-source.json')
    const configPath = path.join(exact, '.git', 'config')
    const attackerOrigin = 'https://example.invalid/attacker/repository.git'
    const changedConfig = fs.readFileSync(configPath, 'utf8').replace(TEST_ORIGIN, attackerOrigin)
    fs.writeFileSync(configPath, changedConfig)
    const receipt = JSON.parse(fs.readFileSync(receiptPath, 'utf8'))
    receipt.originUrl = attackerOrigin
    receipt.configSha256 = require('crypto').createHash('sha256').update(changedConfig).digest('hex')
    fs.writeFileSync(receiptPath, `${JSON.stringify(receipt)}\n`)
    assert.throws(
      () => assertExactBootstrap(exact, commit, TEST_ORIGIN, FIXTURE_TAGS),
      /Git administration|origin|config/i,
      'changing both the config and its writable receipt must not create a self-validating authority'
    )
  })

  withBootstrap('alternates', ({ commit, exact, fixture }) => {
    const alternateObjects = path.join(fixture, 'alternate-objects')
    fs.mkdirSync(alternateObjects)
    fs.mkdirSync(path.join(exact, '.git', 'objects', 'info'), { recursive: true })
    fs.writeFileSync(
      path.join(exact, '.git', 'objects', 'info', 'alternates'),
      `${alternateObjects}\n`
    )
    assert.throws(
      () => assertExactBootstrap(exact, commit, TEST_ORIGIN, FIXTURE_TAGS),
      /alternate.*object|Git administration/i,
      'post-bootstrap alternate object stores must not participate in release verification'
    )
  })

  withBootstrap('common-directory', ({ commit, exact, fixture }) => {
    const common = path.join(fixture, 'external-common.git')
    const hostileHooks = path.join(fixture, 'hostile-hooks')
    fs.cpSync(path.join(exact, '.git'), common, { recursive: true })
    fs.mkdirSync(hostileHooks)
    fs.writeFileSync(path.join(hostileHooks, 'pre-push'), '#!/bin/sh\nexit 0\n')
    fs.chmodSync(path.join(hostileHooks, 'pre-push'), 0o755)
    fs.writeFileSync(
      path.join(common, 'config'),
      fs.readFileSync(path.join(common, 'config'), 'utf8')
        .replace(/hooksPath = .*\n/, `hooksPath = ${hostileHooks}\n`)
    )
    fs.writeFileSync(path.join(exact, '.git', 'commondir'), `${common}\n`)
    assert.throws(
      () => assertExactBootstrap(exact, commit, TEST_ORIGIN, FIXTURE_TAGS),
      /common.*director|split.*Git|linked.*worktree|Git administration/i,
      'an external common Git directory must not replace the receipt-bound config and hooks'
    )
  })

  withBootstrap('replacement-ref', ({ commit, exact }) => {
    const tree = git(exact, ['rev-parse', `${commit}^{tree}`]).trim()
    const substitute = git(exact, ['commit-tree', tree], {
      input: 'feat!: substituted release history\n',
      env: {
        ...process.env,
        GIT_AUTHOR_NAME: 'Exact Source Test',
        GIT_AUTHOR_EMAIL: 'exact-source@example.invalid',
        GIT_COMMITTER_NAME: 'Exact Source Test',
        GIT_COMMITTER_EMAIL: 'exact-source@example.invalid'
      }
    }).trim()
    git(exact, ['replace', commit, substitute])
    assert.throws(
      () => assertExactBootstrap(exact, commit, TEST_ORIGIN, FIXTURE_TAGS),
      /replacement|refs\/replace|history substitution/i,
      'replacement refs must not change the history later consumed by semantic-release'
    )
  })

  withBootstrap('local-only-tag', ({ commit, exact }) => {
    git(exact, ['tag', 'v0.90.0', commit])
    assert.throws(
      () => assertExactBootstrap(exact, commit, TEST_ORIGIN, FIXTURE_TAGS),
      /tag.*(authority|snapshot|remote|namespace)|local-only/i,
      'a local-only version tag must not influence or be pushed by semantic-release'
    )
  })

  console.log('[exact-git-source-integrity-test] OK')
}

main()
