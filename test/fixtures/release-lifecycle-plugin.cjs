const fs = require('fs')
const { execFileSync } = require('child_process')

function git(args, cwd, allowFailure = false) {
  try {
    return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim()
  } catch (error) {
    if (allowFailure) return null
    throw error
  }
}

function hasLocalTag(tag, cwd) {
  return git(['show-ref', '--verify', `refs/tags/${tag}`], cwd, true) !== null
}

function hasRemoteTag(tag, cwd) {
  return git(['ls-remote', '--exit-code', '--tags', 'origin', `refs/tags/${tag}`], cwd, true) !== null
}

function record(phase, context) {
  const tag = context.nextRelease.gitTag
  const statePath = context.env.RELEASE_LIFECYCLE_STATE
  const state = fs.existsSync(statePath)
    ? JSON.parse(fs.readFileSync(statePath, 'utf8'))
    : {}
  state[phase] = {
    head: git(['rev-parse', 'HEAD^{commit}'], context.cwd),
    localTag: hasLocalTag(tag, context.cwd),
    remoteTag: hasRemoteTag(tag, context.cwd),
    tag,
    version: context.nextRelease.version
  }
  fs.writeFileSync(statePath, `${JSON.stringify(state, null, 2)}\n`)
}

async function analyzeCommits() {
  return 'patch'
}

async function verifyRelease(_pluginConfig, context) {
  if (context.nextRelease.version !== '0.1.1') throw new Error('unexpected lifecycle fixture version')
}

async function generateNotes() {
  return 'Lifecycle fixture release.'
}

async function prepare(_pluginConfig, context) {
  record('prepare', context)
  if (context.env.RELEASE_LIFECYCLE_FAIL_PREPARE === '1') {
    throw new Error('injected deterministic preparation failure')
  }
}

async function publish(_pluginConfig, context) {
  record('publish', context)
  return { name: context.nextRelease.gitTag, url: `https://example.invalid/${context.nextRelease.gitTag}` }
}

module.exports = { analyzeCommits, generateNotes, prepare, publish, verifyRelease }
