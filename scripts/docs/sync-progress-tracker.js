#!/usr/bin/env node
/**
 * Sync Beads-backed status blocks in docs.
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

const PROGRESS_START = '<!-- GENERATED:beads-progress:start -->'
const PROGRESS_END = '<!-- GENERATED:beads-progress:end -->'
const VISION_START = '<!-- GENERATED:vision-status:start -->'
const VISION_END = '<!-- GENERATED:vision-status:end -->'

function readUtf8(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function writeUtf8(filePath, content) {
  fs.writeFileSync(filePath, content)
}

function runBdShow(issueId) {
  let raw
  try {
    raw = execFileSync('bd', ['show', issueId, '--json'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    })
  } catch (error) {
    const stderr = error && error.stderr ? String(error.stderr) : ''
    throw new Error(
      `Failed to read Beads issue ${issueId}.` +
        (stderr.length > 0 ? `\n${stderr.trim()}` : '')
    )
  }

  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (error) {
    throw new Error(`Invalid JSON from: bd show ${issueId} --json`)
  }

  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new Error(`Beads issue not found: ${issueId}`)
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
      id: dep.id,
      title: dep.title,
      status: dep.status || 'unknown',
      priority: typeof dep.priority === 'number' ? `P${dep.priority}` : 'n/a'
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

function todayIsoDate() {
  return new Date().toISOString().slice(0, 10)
}

function buildProgressBlock(data) {
  const { generatedOn, foundation, harness, releaseGate, depSummary } = data
  const lines = []

  lines.push(
    `_Generated from Beads on ${generatedOn} via \`npm run docs:sync:progress\`._`
  )
  lines.push('')
  lines.push('| Workstream | Bead | Status |')
  lines.push('| --- | --- | --- |')
  lines.push(
    `| Foundation milestone roadmap | \`${foundation.id}\` | ${statusLabel(foundation.status)} |`
  )
  lines.push(
    `| Advanced TUI stress harness | \`${harness.id}\` | ${statusLabel(harness.status)} |`
  )
  lines.push(
    `| 1.0 release gate | \`${releaseGate.id}\` | ${statusLabel(releaseGate.status)} |`
  )
  lines.push('')
  lines.push(
    `- Release-gate dependency completion: **${depSummary.counts.closed} / ${depSummary.counts.total} closed (${toPercent(depSummary.counts.closed, depSummary.counts.total)})**`
  )
  lines.push(
    `- Remaining release-gate dependencies: **${depSummary.remaining.length}**`
  )

  if (depSummary.remaining.length > 0) {
    lines.push('')
    lines.push('| Remaining dependency | Priority | Status |')
    lines.push('| --- | --- | --- |')
    for (const dep of depSummary.remaining) {
      lines.push(
        `| \`${dep.id}\` ${dep.title} | ${dep.priority} | ${statusLabel(dep.status)} |`
      )
    }
  }

  return lines.join('\n')
}

function buildVisionBlock(data) {
  const { generatedOn, foundation, harness, releaseGate, depSummary } = data
  const lines = []

  lines.push(
    `_Generated from Beads on ${generatedOn} via \`npm run docs:sync:progress\`._`
  )
  lines.push('')
  lines.push('| Vision checkpoint | Source | Status |')
  lines.push('| --- | --- | --- |')
  lines.push(
    `| Milestone roadmap complete | \`${foundation.id}\` | ${statusLabel(foundation.status)} |`
  )
  lines.push(
    `| Real-app harness complete | \`${harness.id}\` | ${statusLabel(harness.status)} |`
  )
  lines.push(
    `| 1.0 parity gate | \`${releaseGate.id}\` | ${statusLabel(releaseGate.status)} |`
  )
  lines.push('')
  lines.push(
    `- 1.0 parity dependencies closed: **${depSummary.counts.closed} / ${depSummary.counts.total} (${toPercent(depSummary.counts.closed, depSummary.counts.total)})**`
  )
  lines.push(
    `- 1.0 parity dependencies still open: **${depSummary.remaining.length}**`
  )

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
  const foundation = runBdShow(ISSUE_IDS.foundation)
  const harness = runBdShow(ISSUE_IDS.harness)
  const releaseGate = runBdShow(ISSUE_IDS.releaseGate)
  const depSummary = summarizeDependencies(releaseGate)
  const generatedOn = todayIsoDate()

  const data = {
    generatedOn,
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
  replaceGeneratedSection(
    VISION_DOC,
    VISION_START,
    VISION_END,
    buildVisionBlock(data)
  )
}

main()
