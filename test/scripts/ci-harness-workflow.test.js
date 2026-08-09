const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')

const root = path.resolve(__dirname, '..', '..')
const workflow = fs.readFileSync(path.join(root, '.github', 'workflows', 'ci.yml'), 'utf8')

function jobBody(jobId, nextJobId) {
  const start = workflow.indexOf(`  ${jobId}:\n`)
  const end = workflow.indexOf(`  ${nextJobId}:\n`, start + 1)

  assert.notEqual(start, -1, `CI workflow must define ${jobId}`)
  assert.notEqual(end, -1, `CI workflow must define ${nextJobId} after ${jobId}`)
  return workflow.slice(start, end)
}

const snapshots = jobBody('harness-snapshots', 'harness-conformance-policy')
const timeout = snapshots.match(/^    timeout-minutes: (\d+)$/m)

assert(timeout, 'snapshot harness job must have an explicit timeout')
assert(
  Number(timeout[1]) >= 60,
  `snapshot harness timeout must cover the observed full-suite runtime; found ${timeout[1]} minutes`
)
assert.match(
  snapshots,
  /HARNESS_STAGES=snapshots HARNESS_SNAPSHOT_JOBS=6 HARNESS_CLEAN_OUTPUTS=1 HARNESS_CLEAN_CACHE=1 bash scripts\/ci\/harness\.sh/,
  'snapshot harness must retain the reviewed parallel, cold-output execution contract'
)

const conformancePolicy = jobBody('harness-conformance-policy', 'harness-examples')
const conformancePolicyTimeout = conformancePolicy.match(/^    timeout-minutes: (\d+)$/m)

assert(conformancePolicyTimeout, 'conformance and policy harness job must have an explicit timeout')
assert(
  Number(conformancePolicyTimeout[1]) >= 75,
  `conformance and policy timeout must cover the observed full-suite runtime; found ${conformancePolicyTimeout[1]} minutes`
)
assert.match(
  conformancePolicy,
  /HARNESS_STAGES="conformance policy" HARNESS_CLEAN_OUTPUTS=1 HARNESS_CLEAN_CACHE=1 bash scripts\/ci\/harness\.sh/,
  'conformance and policy harness must retain its reviewed cold execution contract'
)

console.log('[ci-harness-workflow-test] OK')
