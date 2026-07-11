#!/usr/bin/env node

const assert = require('assert')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')

async function main() {
  const releaseConfig = require(path.join(repoRoot, 'release.config.js'))
  const configured = releaseConfig.plugins.find((entry) => Array.isArray(entry) && entry[0] === '@semantic-release/release-notes-generator')
  assert(configured, 'release configuration must include the release-notes generator')

  const { generateNotes } = await import('@semantic-release/release-notes-generator')
  const notes = await generateNotes(configured[1] || {}, {
    cwd: repoRoot,
    commits: [
      { hash: '1111111111111111111111111111111111111111', message: 'fix(core): preserve generated behavior' },
      { hash: '2222222222222222222222222222222222222222', message: 'feat: add a typed facade' },
      { hash: '3333333333333333333333333333333333333333', message: 'perf: reduce allocation overhead' },
      { hash: '4444444444444444444444444444444444444444', message: 'feat!: replace an initial-development API' },
      { hash: '5555555555555555555555555555555555555555', message: 'fix: restore the contract\n\nBREAKING CHANGE: callers must migrate' },
      { hash: '6666666666666666666666666666666666666666', message: 'docs: update internal guidance' },
      { hash: '7777777777777777777777777777777777777777', message: 'chore: refresh bookkeeping' }
    ],
    lastRelease: { gitTag: 'v0.85.0', gitHead: '0000000000000000000000000000000000000000' },
    nextRelease: { version: '0.86.0', gitTag: 'v0.86.0', gitHead: '7777777777777777777777777777777777777777' },
    options: { repositoryUrl: 'https://github.com/fullofcaffeine/reflaxe.rust.git' }
  })

  assert.match(notes, /Bug Fixes/)
  assert.match(notes, /\* \*\*core:\*\* preserve generated behavior/)
  assert.match(notes, /Features/)
  assert.match(notes, /add a typed facade/)
  assert.match(notes, /Performance Improvements/)
  assert.match(notes, /reduce allocation overhead/)
  assert.match(notes, /replace an initial-development API/)
  assert.match(notes, /BREAKING CHANGES/)
  assert.match(notes, /callers must migrate/)
  assert.doesNotMatch(notes, /update internal guidance/)
  assert.doesNotMatch(notes, /refresh bookkeeping/)

  console.log('[release-notes-test] OK')
}

main().catch((error) => {
  console.error(error.stack || error.message)
  process.exit(1)
})
