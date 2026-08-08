const assert = require('node:assert')
const { evaluateAudit } = require('../../scripts/ci/npm-audit-policy')

const approvedUrl = 'https://github.com/advisories/GHSA-8xcm-r25x-g524'
const activeOptions = {
  now: Date.parse('2026-08-08T00:00:00Z'),
  plugins: ['./scripts/release/semantic-release-policy.cjs']
}

function report(overrides = {}) {
  return {
    vulnerabilities: {
      undici: {
        severity: 'moderate',
        nodes: ['node_modules/npm/node_modules/undici'],
        via: [{ url: approvedUrl }]
      },
      npm: {
        severity: 'moderate',
        nodes: ['node_modules/npm'],
        via: ['undici']
      },
      '@semantic-release/npm': {
        severity: 'moderate',
        nodes: ['node_modules/@semantic-release/npm'],
        via: ['npm']
      },
      'semantic-release': {
        severity: 'moderate',
        nodes: ['node_modules/semantic-release'],
        via: ['@semantic-release/npm']
      },
      ...overrides
    }
  }
}

const accepted = evaluateAudit(report(), activeOptions)
assert.deepStrictEqual(accepted.accepted, [approvedUrl])

assert.throws(
  () => evaluateAudit(report({ surprise: { severity: 'high', nodes: ['node_modules/surprise'], via: [{ url: approvedUrl }] } }), activeOptions),
  /unapproved vulnerable package surprise/
)
assert.throws(
  () => evaluateAudit(report({ undici: { severity: 'high', nodes: ['node_modules/npm/node_modules/undici'], via: [{ url: 'https:\/\/example.invalid\/new' }] } }), activeOptions),
  /unapproved advisory/
)
assert.throws(
  () => evaluateAudit(report({ undici: { severity: 'high', nodes: ['node_modules/undici'], via: [{ url: approvedUrl }] } }), activeOptions),
  /outside its approved unused path/
)
assert.throws(
  () => evaluateAudit(report({ undici: { severity: 'critical', nodes: ['node_modules/npm/node_modules/undici'], via: [{ url: approvedUrl }] } }), activeOptions),
  /critical severity/
)
assert.throws(
  () => evaluateAudit(report(), { plugins: ['@semantic-release/npm'] }),
  /npm publishing plugin is active/
)
assert.throws(
  () => evaluateAudit(report(), { now: Date.parse('2026-09-30T00:00:00Z') }),
  /exception expired/
)

console.log('[npm-audit-policy.test] OK')
