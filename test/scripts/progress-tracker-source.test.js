#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const syncScript = path.join(repoRoot, 'scripts', 'docs', 'sync-progress-tracker.js')

function issue(id, fields = {}) {
  return { _type: 'issue', id, title: id, status: 'closed', issue_type: 'task', ...fields }
}

function writeFixture(root, rows) {
  fs.mkdirSync(path.join(root, '.beads'), { recursive: true })
  fs.mkdirSync(path.join(root, 'docs'), { recursive: true })
  fs.mkdirSync(path.join(root, 'bin'), { recursive: true })
  fs.writeFileSync(path.join(root, '.beads', 'issues.jsonl'), `${rows.map((row) => JSON.stringify(row)).join('\n')}\n`)
  fs.writeFileSync(path.join(root, 'docs', 'progress-tracker.md'), '<!-- GENERATED:progress-status:start -->\nold\n<!-- GENERATED:progress-status:end -->\n')
  fs.writeFileSync(path.join(root, 'docs', 'vision-vs-implementation.md'), '<!-- GENERATED:vision-status:start -->\nold\n<!-- GENERATED:vision-status:end -->\n')
  const fakeBd = path.join(root, 'bin', 'bd')
  fs.writeFileSync(fakeBd, '#!/usr/bin/env node\nprocess.stderr.write("no local database\\n")\nprocess.exit(1)\n')
  fs.chmodSync(fakeBd, 0o755)
}

function runFixture(root) {
  return cp.spawnSync(process.execPath, [syncScript], {
    cwd: root,
    env: { ...process.env, PATH: `${path.join(root, 'bin')}${path.delimiter}${process.env.PATH}` },
    encoding: 'utf8'
  })
}

const moduleUnderTest = require('../../scripts/docs/sync-progress-tracker.js')
assert.strictEqual(typeof moduleUnderTest.runIssueShowFromBd, 'function',
  'the live tracker reader must be independently testable')
const observedCalls = []
const shown = moduleUnderTest.runIssueShowFromBd('roadmap', (_command, args) => {
  observedCalls.push(args)
  if (args.includes('--children')) {
    return JSON.stringify({
      roadmap: [issue('current', {
        dependency_type: 'parent-child',
        labels: ['release-hardening']
      })]
    })
  }
  return JSON.stringify([issue('roadmap', { dependent_count: 1, dependents: [] })])
})
assert.strictEqual(shown.id, 'roadmap')
assert(observedCalls.some((args) => args.includes('--include-dependents')),
  'live tracker reads must request reverse relationships so roadmap children are visible')
assert(observedCalls.some((args) => args.includes('--children')),
  'live tracker reads must request complete child records so labels and dates remain available')
assert.deepStrictEqual(shown.dependents.map((dependent) => dependent.id), ['current'])

const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-progress-source-'))
try {
  const roadmap = issue('haxe.rust-oo3', { issue_type: 'epic' })
  const milestone = issue('milestone', {
    title: 'Milestone current release review',
    issue_type: 'epic',
    labels: ['release-hardening'],
    dependencies: [{ issue_id: 'milestone', depends_on_id: roadmap.id, type: 'parent-child' }]
  })
  const child = issue('child', {
    dependencies: [{ issue_id: 'child', depends_on_id: milestone.id, type: 'parent-child' }]
  })
  const harness = issue('haxe.rust-cu0')
  const historical = issue('haxe.rust-4jb')
  writeFixture(fixture, [roadmap, milestone, child, harness, historical])

  const cleanResult = runFixture(fixture)
  assert.strictEqual(cleanResult.status, 0, `${cleanResult.stdout}\n${cleanResult.stderr}`)
  assert.match(cleanResult.stderr, /using \.beads\/issues\.jsonl fallback/)
  assert.match(fs.readFileSync(path.join(fixture, 'docs', 'progress-tracker.md'), 'utf8'),
    /Hardening checklist completion: \*\*1 \/ 1 closed \(100%\)\*\*/)

  fs.writeFileSync(path.join(fixture, '.beads', 'issues.jsonl'), '{broken json\n')
  const malformedResult = runFixture(fixture)
  assert.notStrictEqual(malformedResult.status, 0, 'malformed tracked issue data must fail')
  assert.match(malformedResult.stderr, /Invalid JSON in \.beads\/issues\.jsonl:1/)
} finally {
  fs.rmSync(fixture, { recursive: true, force: true })
}

console.log('[progress-tracker-source-test] OK')
