#!/usr/bin/env node
/**
 * Print a prefilled release closeout evidence block.
 *
 * Usage:
 *   npm run docs:prep:closeout
 */

const { execFileSync } = require('child_process')

const GATE_ID = 'haxe.rust-4jb'

function runIssueShow(issueId) {
  let raw
  try {
    raw = execFileSync('bd', ['show', issueId, '--json'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    })
  } catch (error) {
    const stderr = error && error.stderr ? String(error.stderr).trim() : ''
    const suffix = stderr.length > 0 ? `\n${stderr}` : ''
    throw new Error(`Failed to read internal tracker issue ${issueId}.${suffix}`)
  }

  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (_error) {
    throw new Error(`Invalid JSON from: bd show ${issueId} --json`)
  }

  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new Error(`Tracker issue not found: ${issueId}`)
  }

  return parsed[0]
}

function todayIsoDate() {
  return new Date().toISOString().slice(0, 10)
}

function main() {
  const gate = runIssueShow(GATE_ID)
  const deps = Array.isArray(gate.dependencies) ? gate.dependencies : []
  const closedDeps = deps.filter((dep) => dep.status === 'closed')
  const remainingDeps = deps.filter((dep) => dep.status !== 'closed')

  const lines = []
  lines.push('1.0 closeout evidence (' + todayIsoDate() + ')')
  lines.push('')
  lines.push('- Release gate status at review time: ' + (gate.status || 'unknown'))
  lines.push('- Checklist completion: ' + closedDeps.length + '/' + deps.length + ' closed')

  if (remainingDeps.length > 0) {
    lines.push('- Remaining checklist items:')
    for (const dep of remainingDeps) {
      lines.push('  - (' + (dep.status || 'unknown') + ') ' + dep.title)
    }
  } else {
    lines.push('- Remaining checklist items: none')
  }

  lines.push('')
  lines.push('Validation runs:')
  lines.push('- npm run docs:sync:progress -> PASS|FAIL')
  lines.push('- npm run docs:check:progress -> PASS|FAIL')
  lines.push('- bash scripts/ci/local.sh -> PASS|FAIL')
  lines.push('- bash scripts/ci/windows-smoke.sh -> PASS|SKIPPED (reason)|FAIL')
  lines.push('')
  lines.push('Docs alignment checks:')
  lines.push('- README 1.0 docs index reviewed')
  lines.push('- docs/start-here.md reviewed')
  lines.push('- docs/progress-tracker.md synced')
  lines.push('- docs/vision-vs-implementation.md synced')
  lines.push('- docs/defines-reference.md reviewed')
  lines.push('- docs/road-to-1.0.md reviewed')
  lines.push('- docs/release-gate-closeout.md reviewed')
  lines.push('')
  lines.push('Residual risks:')
  lines.push('- <list, or "none">')
  lines.push('')
  lines.push('Decision:')
  lines.push('- Declare release gate closed now: YES|NO')
  lines.push('- If NO, next action + owner + target date: <...>')

  process.stdout.write(lines.join('\n') + '\n')
}

main()
