#!/usr/bin/env node

const { spawnSync } = require('node:child_process')
const path = require('node:path')

const rootDir = path.resolve(__dirname, '../..')
const exceptionExpiresAt = Date.parse('2026-09-30T00:00:00Z')

// These advisories currently come only from npm's bundled files inside the
// unused @semantic-release/npm plugin. New advisories are not accepted.
const allowedAdvisories = new Set([
  'https://github.com/advisories/GHSA-mh99-v99m-4gvg',
  'https://github.com/advisories/GHSA-rgw5-rvv9-x895',
  'https://github.com/advisories/GHSA-mwp4-54f8-5fhr',
  'https://github.com/advisories/GHSA-4xrf-jv44-h6hh',
  'https://github.com/advisories/GHSA-22jq-vg5j-6vgg',
  'https://github.com/advisories/GHSA-r292-9mhp-454m',
  'https://github.com/advisories/GHSA-8xcm-r25x-g524',
  'https://github.com/advisories/GHSA-m8rv-5g2x-5cg5',
  'https://github.com/advisories/GHSA-v3r7-h72x-cjcm'
])

const allowedNodes = new Map([
  ['brace-expansion', /^node_modules\/npm\/node_modules\/brace-expansion$/],
  ['ip-address', /^node_modules\/npm\/node_modules\/ip-address$/],
  ['tar', /^node_modules\/npm\/node_modules\/tar$/],
  ['undici', /^node_modules\/npm\/node_modules\/undici$/],
  ['npm', /^node_modules\/npm$/],
  ['@semantic-release/npm', /^node_modules\/@semantic-release\/npm$/],
  ['semantic-release', /^node_modules\/semantic-release$/]
])

function pluginName(plugin) {
  return Array.isArray(plugin) ? plugin[0] : plugin
}

function collectLeafAdvisories(vulnerabilities, name, active = new Set()) {
  if (active.has(name)) {
    throw new Error(`npm audit dependency cycle at ${name}`)
  }

  const vulnerability = vulnerabilities[name]
  if (vulnerability == null) {
    throw new Error(`npm audit references missing vulnerability ${name}`)
  }

  const nextActive = new Set(active)
  nextActive.add(name)
  const leaves = []

  for (const cause of vulnerability.via || []) {
    if (typeof cause === 'string') {
      leaves.push(...collectLeafAdvisories(vulnerabilities, cause, nextActive))
    } else if (cause != null && typeof cause === 'object') {
      leaves.push(cause)
    } else {
      throw new Error(`npm audit returned an unsupported cause for ${name}`)
    }
  }

  if (leaves.length === 0) {
    throw new Error(`npm audit returned no concrete advisory for ${name}`)
  }
  return leaves
}

function evaluateAudit(report, options = {}) {
  const now = options.now == null ? Date.now() : options.now
  const plugins = options.plugins || []
  const vulnerabilities = report == null ? null : report.vulnerabilities

  if (vulnerabilities == null || typeof vulnerabilities !== 'object') {
    throw new Error('npm audit did not return a vulnerability map')
  }
  if (Object.keys(vulnerabilities).length === 0) {
    return { accepted: [], total: 0 }
  }
  if (now >= exceptionExpiresAt) {
    throw new Error('the narrow npm audit exception expired on 2026-09-30')
  }
  if (plugins.map(pluginName).includes('@semantic-release/npm')) {
    throw new Error('the npm publishing plugin is active, so its dependency findings cannot be excepted')
  }

  const accepted = new Set()
  for (const [name, vulnerability] of Object.entries(vulnerabilities)) {
    const nodePattern = allowedNodes.get(name)
    if (nodePattern == null) {
      throw new Error(`npm audit found unapproved vulnerable package ${name}`)
    }
    if (vulnerability.severity === 'critical') {
      throw new Error(`npm audit raised ${name} to critical severity`)
    }
    if (!Array.isArray(vulnerability.nodes) || vulnerability.nodes.length === 0) {
      throw new Error(`npm audit returned no installed path for ${name}`)
    }
    for (const node of vulnerability.nodes) {
      if (!nodePattern.test(node)) {
        throw new Error(`npm audit found ${name} outside its approved unused path: ${node}`)
      }
    }
    for (const advisory of collectLeafAdvisories(vulnerabilities, name)) {
      if (!allowedAdvisories.has(advisory.url)) {
        throw new Error(`npm audit found unapproved advisory ${advisory.url || '<missing URL>'}`)
      }
      accepted.add(advisory.url)
    }
  }

  return { accepted: [...accepted].sort(), total: Object.keys(vulnerabilities).length }
}

function run() {
  const audit = spawnSync('npm', ['audit', '--json'], {
    cwd: rootDir,
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024
  })
  if (audit.error != null) {
    throw audit.error
  }

  let report
  try {
    report = JSON.parse(audit.stdout)
  } catch (error) {
    throw new Error(`npm audit returned invalid JSON: ${error.message}`)
  }

  const releaseConfig = require(path.join(rootDir, 'release.config.js'))
  const result = evaluateAudit(report, { plugins: releaseConfig.plugins })
  if (audit.status !== 0 && result.accepted.length === 0) {
    throw new Error(`npm audit failed with status ${audit.status} but reported no approved advisory`)
  }

  if (result.accepted.length === 0) {
    console.log('[npm-audit-policy] OK: no known vulnerabilities')
  } else {
    console.log(
      `[npm-audit-policy] OK with temporary unused-plugin exception: ${result.accepted.length} exact advisories across ${result.total} reported packages`
    )
  }
}

if (require.main === module) {
  try {
    run()
  } catch (error) {
    console.error(`[npm-audit-policy] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = { evaluateAudit }
