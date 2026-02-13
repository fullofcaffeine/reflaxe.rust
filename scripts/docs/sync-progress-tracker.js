#!/usr/bin/env node
/**
 * Sync internal-tracker-backed status blocks in docs.
 *
 * Usage:
 *   npm run docs:sync:progress
 */

const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')

const ISSUE_IDS = {
  foundation: 'haxe.rust-oo3',
  harness: 'haxe.rust-cu0',
  releaseGate: 'haxe.rust-4jb'
}

const PROGRESS_DOC = 'docs/progress-tracker.md'
const VISION_DOC = 'docs/vision-vs-implementation.md'

const PROGRESS_START = '<!-- GENERATED:progress-status:start -->'
const PROGRESS_END = '<!-- GENERATED:progress-status:end -->'
const VISION_START = '<!-- GENERATED:vision-status:start -->'
const VISION_END = '<!-- GENERATED:vision-status:end -->'

function readUtf8(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function writeUtf8(filePath, content) {
  fs.writeFileSync(filePath, content)
}

function runIssueShow(issueId) {
  let raw
  try {
    raw = execFileSync('bd', ['show', issueId, '--json'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    })
  } catch (error) {
    const stderr = error && error.stderr ? String(error.stderr) : ''
    throw new Error(
      `Failed to read internal tracker issue ${issueId}.` +
        (stderr.length > 0 ? `\n${stderr.trim()}` : '')
    )
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

function summarizeDependencies(issue) {
  const dependencies = Array.isArray(issue.dependencies) ? issue.dependencies : []
  const counts = {
    total: dependencies.length,
    closed: 0,
    in_progress: 0,
    open: 0,
    blocked: 0,
    deferred: 0,
    other: 0
  }

  for (const dep of dependencies) {
    const status = dep.status || 'other'
    if (Object.prototype.hasOwnProperty.call(counts, status)) {
      counts[status] += 1
    } else {
      counts.other += 1
    }
  }

  const remaining = dependencies
    .filter((dep) => dep.status !== 'closed')
    .map((dep) => ({
      title: dep.title,
      status: dep.status || 'unknown'
    }))

  return {
    counts,
    remaining
  }
}

function statusLabel(status) {
  switch (status) {
    case 'closed':
      return 'closed'
    case 'in_progress':
      return 'in progress'
    case 'open':
      return 'open'
    case 'blocked':
      return 'blocked'
    case 'deferred':
      return 'deferred'
    default:
      return status || 'unknown'
  }
}

function toPercent(value, total) {
  if (total <= 0) return 'n/a'
  return `${Math.round((value / total) * 100)}%`
}

function buildProgressBlock(data) {
  const { foundation, harness, releaseGate, depSummary } = data
  const lines = []

  lines.push(
    '_Status snapshot generated from the internal release tracker via `npm run docs:sync:progress`._'
  )
  lines.push('')
  lines.push('| Workstream | What this means | Status |')
  lines.push('| --- | --- | --- |')
  lines.push(
    `| Core compiler/runtime foundation | Core language lowering, runtime primitives, and toolchain flow are in place. | ${statusLabel(foundation.status)} |`
  )
  lines.push(
    `| Real-application stress harness | Non-trivial app coverage validates behavior under realistic usage. | ${statusLabel(harness.status)} |`
  )
  lines.push(
    `| Production release gate | Final parity + docs + CI evidence checklist is complete. | ${statusLabel(releaseGate.status)} |`
  )
  lines.push('')
  lines.push(
    `- Release-gate checklist completion: **${depSummary.counts.closed} / ${depSummary.counts.total} closed (${toPercent(depSummary.counts.closed, depSummary.counts.total)})**`
  )
  lines.push(`- Remaining release-gate checks: **${depSummary.remaining.length}**`)

  if (depSummary.remaining.length > 0) {
    lines.push('')
    lines.push('| Outstanding check | Status |')
    lines.push('| --- | --- |')
    for (const dep of depSummary.remaining) {
      lines.push(`| ${dep.title} | ${statusLabel(dep.status)} |`)
    }
  }

  return lines.join('\n')
}

function buildVisionBlock(data) {
  const { foundation, harness, releaseGate, depSummary } = data
  const lines = []

  lines.push(
    '_Status snapshot generated from the internal release tracker via `npm run docs:sync:progress`._'
  )
  lines.push('')
  lines.push('| Vision checkpoint | What this means | Status |')
  lines.push('| --- | --- | --- |')
  lines.push(
    `| Foundation complete | Core compiler/runtime architecture is stable. | ${statusLabel(foundation.status)} |`
  )
  lines.push(
    `| Real-app harness complete | App-scale behavior is validated in CI-style flows. | ${statusLabel(harness.status)} |`
  )
  lines.push(
    `| 1.0 parity gate complete | Final production-readiness criteria are met. | ${statusLabel(releaseGate.status)} |`
  )
  lines.push('')
  lines.push(
    `- 1.0 parity checks closed: **${depSummary.counts.closed} / ${depSummary.counts.total} (${toPercent(depSummary.counts.closed, depSummary.counts.total)})**`
  )
  lines.push(`- 1.0 parity checks still open: **${depSummary.remaining.length}**`)

  return lines.join('\n')
}

function replaceGeneratedSection(filePath, startMarker, endMarker, replacement) {
  const absolutePath = path.resolve(filePath)
  const original = readUtf8(absolutePath)
  const startIndex = original.indexOf(startMarker)
  const endIndex = original.indexOf(endMarker)

  if (startIndex === -1 || endIndex === -1 || endIndex <= startIndex) {
    throw new Error(
      `Missing or invalid generated markers in ${filePath}: ${startMarker} ... ${endMarker}`
    )
  }

  const before = original.slice(0, startIndex + startMarker.length)
  const after = original.slice(endIndex)
  const next = `${before}\n${replacement}\n${after}`

  if (next !== original) {
    writeUtf8(absolutePath, next)
  }
}

function main() {
  const foundation = runIssueShow(ISSUE_IDS.foundation)
  const harness = runIssueShow(ISSUE_IDS.harness)
  const releaseGate = runIssueShow(ISSUE_IDS.releaseGate)
  const depSummary = summarizeDependencies(releaseGate)

  const data = {
    foundation,
    harness,
    releaseGate,
    depSummary
  }

  replaceGeneratedSection(
    PROGRESS_DOC,
    PROGRESS_START,
    PROGRESS_END,
    buildProgressBlock(data)
  )
  replaceGeneratedSection(VISION_DOC, VISION_START, VISION_END, buildVisionBlock(data))
}

main()
