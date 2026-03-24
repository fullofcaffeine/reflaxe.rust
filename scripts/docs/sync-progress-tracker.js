#!/usr/bin/env node
/**
 * Sync tracker-backed status blocks in docs.
 *
 * Why:
 *   The public docs must reflect the real roadmap state, not a hand-maintained
 *   summary that drifts. The previous implementation treated the umbrella
 *   roadmap epic as the "foundation complete" signal, which guaranteed a false
 *   `open` status forever and let status docs contradict the actual milestone
 *   baseline.
 *
 * What:
 *   This script derives three reviewable signals:
 *   - closed implementation baseline under the roadmap epic,
 *   - real-app harness status,
 *   - the current release-hardening milestone and its child-task checklist.
 *
 * How:
 *   Prefer `bd show --json` when available so in-session tracker state is used.
 *   Fall back to `.beads/issues.jsonl` when `bd` is unavailable. In both modes,
 *   the script resolves parent/child relationships so the generated docs track
 *   milestone reality instead of umbrella-epic liveness.
 *
 * Usage:
 *   npm run docs:sync:progress
 */

const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')

const ISSUE_IDS = {
  roadmap: 'haxe.rust-oo3',
  harness: 'haxe.rust-cu0',
  historicalReleaseGate: 'haxe.rust-4jb'
}

const PROGRESS_DOC = 'docs/progress-tracker.md'
const VISION_DOC = 'docs/vision-vs-implementation.md'

const PROGRESS_START = '<!-- GENERATED:progress-status:start -->'
const PROGRESS_END = '<!-- GENERATED:progress-status:end -->'
const VISION_START = '<!-- GENERATED:vision-status:start -->'
const VISION_END = '<!-- GENERATED:vision-status:end -->'
const BEADS_ISSUES_JSONL = '.beads/issues.jsonl'

let cachedIssuesById = null

function readUtf8(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function writeUtf8(filePath, content) {
  fs.writeFileSync(filePath, content)
}

function parseIssueShowJson(raw, commandLabel) {
  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (_error) {
    throw new Error(`Invalid JSON from: ${commandLabel}`)
  }

  if (!Array.isArray(parsed) || parsed.length === 0) {
    throw new Error(`Tracker issue not found for: ${commandLabel}`)
  }

  return parsed[0]
}

function runIssueShowFromBd(issueId) {
  let raw
  try {
    raw = execFileSync('bd', ['show', issueId, '--json'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    })
  } catch (error) {
    const stderr = error && error.stderr ? String(error.stderr) : ''
    const message =
      `Failed to read internal tracker issue ${issueId} via bd.` +
      (stderr.length > 0 ? `\n${stderr.trim()}` : '')
    throw new Error(message)
  }

  return parseIssueShowJson(raw, `bd show ${issueId} --json`)
}

function parseIssueJsonl(line, lineNumber) {
  try {
    return JSON.parse(line)
  } catch (_error) {
    throw new Error(`Invalid JSON in ${BEADS_ISSUES_JSONL}:${lineNumber}`)
  }
}

function loadIssuesByIdFromJsonl() {
  if (cachedIssuesById !== null) {
    return cachedIssuesById
  }

  const issuesPath = path.resolve(BEADS_ISSUES_JSONL)
  if (!fs.existsSync(issuesPath)) {
    throw new Error(`Fallback tracker data not found: ${BEADS_ISSUES_JSONL}`)
  }

  const issuesById = new Map()
  const raw = readUtf8(issuesPath)
  const lines = raw.split(/\r?\n/)
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i].trim()
    if (line.length === 0) {
      continue
    }

    const issue = parseIssueJsonl(line, i + 1)
    if (issue && typeof issue.id === 'string' && issue.id.length > 0) {
      issuesById.set(issue.id, issue)
    }
  }

  cachedIssuesById = issuesById
  return issuesById
}

function buildExpandedIssueFromJsonl(issue, issuesById) {
  const dependencies = Array.isArray(issue.dependencies) ? issue.dependencies : []
  const expandedDependencies = dependencies.map((dep) => {
    const dependsOnId =
      typeof dep.depends_on_id === 'string' && dep.depends_on_id.length > 0
        ? dep.depends_on_id
        : ''
    const relatedIssue = dependsOnId.length > 0 ? issuesById.get(dependsOnId) : null

    return {
      id: dependsOnId,
      title: relatedIssue && relatedIssue.title ? relatedIssue.title : dependsOnId || 'unknown',
      status: relatedIssue && relatedIssue.status ? relatedIssue.status : 'unknown',
      issue_type: relatedIssue && relatedIssue.issue_type ? relatedIssue.issue_type : 'unknown',
      created_at: relatedIssue && relatedIssue.created_at ? relatedIssue.created_at : '',
      labels: relatedIssue && Array.isArray(relatedIssue.labels) ? relatedIssue.labels : [],
      dependency_type: dep.type || 'unknown'
    }
  })

  const dependents = []
  for (const candidate of issuesById.values()) {
    const candidateDependencies = Array.isArray(candidate.dependencies) ? candidate.dependencies : []
    for (const dep of candidateDependencies) {
      if (dep.depends_on_id === issue.id) {
        dependents.push({
          id: candidate.id,
          title: candidate.title,
          status: candidate.status || 'unknown',
          issue_type: candidate.issue_type || 'unknown',
          created_at: candidate.created_at || '',
          labels: Array.isArray(candidate.labels) ? candidate.labels : [],
          dependency_type: dep.type || 'unknown'
        })
      }
    }
  }

  const parentDependency = expandedDependencies.find((dep) => dep.dependency_type === 'parent-child')

  return {
    ...issue,
    dependencies: expandedDependencies,
    dependents,
    parent: parentDependency ? parentDependency.id : null
  }
}

function runIssueShowFromJsonl(issueId) {
  const issuesById = loadIssuesByIdFromJsonl()
  const issue = issuesById.get(issueId)
  if (!issue) {
    throw new Error(`Tracker issue not found in ${BEADS_ISSUES_JSONL}: ${issueId}`)
  }

  return buildExpandedIssueFromJsonl(issue, issuesById)
}

function resolveIssueReader() {
  try {
    const roadmapIssue = runIssueShowFromBd(ISSUE_IDS.roadmap)
    return {
      reader: runIssueShowFromBd,
      sourceLabel: 'bd',
      roadmapIssue
    }
  } catch (error) {
    const details = error && error.message ? error.message : String(error)
    process.stderr.write(
      `[docs] bd unavailable; using ${BEADS_ISSUES_JSONL} fallback for progress sync.\n`
    )
    process.stderr.write(`[docs] bd probe details: ${details}\n`)
    loadIssuesByIdFromJsonl()
    return {
      reader: runIssueShowFromJsonl,
      sourceLabel: BEADS_ISSUES_JSONL
    }
  }
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

function hasLabel(issue, label) {
  return Array.isArray(issue.labels) && issue.labels.includes(label)
}

function summarizeIssues(issues) {
  const counts = {
    total: issues.length,
    closed: 0,
    in_progress: 0,
    open: 0,
    blocked: 0,
    deferred: 0,
    other: 0
  }

  for (const issue of issues) {
    const status = issue.status || 'other'
    if (Object.prototype.hasOwnProperty.call(counts, status)) {
      counts[status] += 1
    } else {
      counts.other += 1
    }
  }

  const remaining = issues
    .filter((issue) => issue.status !== 'closed')
    .map((issue) => ({
      title: issue.title,
      status: issue.status || 'unknown'
    }))

  return {
    counts,
    remaining
  }
}

function summarizeChildIssues(issue) {
  const dependents = Array.isArray(issue.dependents) ? issue.dependents : []
  const children = dependents.filter((dep) => dep.dependency_type === 'parent-child')
  return summarizeIssues(children)
}

function summarizeProgressIssue(issue) {
  const childSummary = summarizeChildIssues(issue)
  if (childSummary.counts.total > 0) {
    return childSummary
  }

  return summarizeDependencies(issue)
}

function milestoneChildren(roadmapIssue) {
  const dependents = Array.isArray(roadmapIssue.dependents) ? roadmapIssue.dependents : []
  return dependents.filter(
    (dep) => dep.dependency_type === 'parent-child' && typeof dep.title === 'string' && dep.title.startsWith('Milestone ')
  )
}

function currentReleaseHardeningMilestone(roadmapIssue) {
  const milestones = milestoneChildren(roadmapIssue)
  const hardening = milestones
    .filter((issue) => hasLabel(issue, 'release-hardening'))
    .sort((a, b) => String(a.created_at || '').localeCompare(String(b.created_at || '')))

  if (hardening.length === 0) {
    return null
  }

  const openOrActive = hardening.find((issue) => issue.status !== 'closed')
  return openOrActive || hardening[hardening.length - 1]
}

function isReviewOnlyMilestone(issue) {
  return hasLabel(issue, 'release-hardening') || hasLabel(issue, 'ga-review')
}

function buildFoundationBaseline(roadmapIssue, activeHardening) {
  const milestones = milestoneChildren(roadmapIssue)
  const baselineMilestones = milestones.filter((issue) => {
    if (activeHardening && issue.id === activeHardening.id) {
      return false
    }

    return !isReviewOnlyMilestone(issue)
  })
  const summary = summarizeIssues(baselineMilestones)

  return {
    title: 'Core compiler/runtime baseline',
    status: summary.remaining.length === 0 ? 'closed' : 'in_progress',
    summary
  }
}

function toPercent(value, total) {
  if (total <= 0) return 'n/a'
  return `${Math.round((value / total) * 100)}%`
}

function hardeningWorkstreamMeaning(status) {
  if (status === 'closed') {
    return 'Status docs, semantic-confidence evidence, and readiness claims have been hardened against the current proof depth.'
  }
  return 'Status docs, semantic-confidence evidence, and readiness claims are being hardened before stronger public release language is used.'
}

function hardeningVisionTitle(status) {
  if (status === 'closed') {
    return 'Release-evidence hardening closed'
  }
  return 'Release-evidence hardening active'
}

function hardeningVisionMeaning(status) {
  if (status === 'closed') {
    return 'Public readiness claims, semantic proof depth, and tracker truth were aligned in the latest hardening tranche.'
  }
  return 'Public readiness claims, semantic proof depth, and tracker truth are being aligned.'
}

function buildProgressBlock(data) {
  const { foundation, harness, hardening, hardeningSummary } = data
  const lines = []

  lines.push(
    '_Status snapshot generated from the internal tracker via `npm run docs:sync:progress`._'
  )
  lines.push('')
  lines.push('| Workstream | What this means | Status |')
  lines.push('| --- | --- | --- |')
  lines.push(
    `| ${foundation.title} | Core language lowering, runtime primitives, and the validated milestone baseline are in place. | ${statusLabel(foundation.status)} |`
  )
  lines.push(
    `| Real-application stress harness | Non-trivial app coverage validates behavior under realistic usage. | ${statusLabel(harness.status)} |`
  )
  lines.push(
    `| Release-evidence hardening | ${hardeningWorkstreamMeaning(hardening.status)} | ${statusLabel(hardening.status)} |`
  )
  lines.push('')
  lines.push(
    `- Hardening checklist completion: **${hardeningSummary.counts.closed} / ${hardeningSummary.counts.total} closed (${toPercent(hardeningSummary.counts.closed, hardeningSummary.counts.total)})**`
  )
  lines.push(`- Remaining hardening checks: **${hardeningSummary.remaining.length}**`)

  if (hardeningSummary.remaining.length > 0) {
    lines.push('')
    lines.push('| Outstanding check | Status |')
    lines.push('| --- | --- |')
    for (const dep of hardeningSummary.remaining) {
      lines.push(`| ${dep.title} | ${statusLabel(dep.status)} |`)
    }
  }

  return lines.join('\n')
}

function buildVisionBlock(data) {
  const { foundation, harness, hardening, hardeningSummary } = data
  const lines = []

  lines.push(
    '_Status snapshot generated from the internal tracker via `npm run docs:sync:progress`._'
  )
  lines.push('')
  lines.push('| Vision checkpoint | What this means | Status |')
  lines.push('| --- | --- | --- |')
  lines.push(
    `| Baseline milestones complete | Core compiler/runtime architecture is stable across the closed milestone baseline. | ${statusLabel(foundation.status)} |`
  )
  lines.push(
    `| Real-app harness complete | App-scale behavior is validated in CI-style flows. | ${statusLabel(harness.status)} |`
  )
  lines.push(
    `| ${hardeningVisionTitle(hardening.status)} | ${hardeningVisionMeaning(hardening.status)} | ${statusLabel(hardening.status)} |`
  )
  lines.push('')
  lines.push(
    `- Release-evidence hardening checks closed: **${hardeningSummary.counts.closed} / ${hardeningSummary.counts.total} (${toPercent(hardeningSummary.counts.closed, hardeningSummary.counts.total)})**`
  )
  lines.push(`- Release-evidence hardening checks still open: **${hardeningSummary.remaining.length}**`)

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
  const issueReader = resolveIssueReader()
  const roadmap = issueReader.roadmapIssue || issueReader.reader(ISSUE_IDS.roadmap)
  const harness = issueReader.reader(ISSUE_IDS.harness)
  const hardeningStub = currentReleaseHardeningMilestone(roadmap)
  const hardening = hardeningStub
    ? issueReader.reader(hardeningStub.id)
    : issueReader.reader(ISSUE_IDS.historicalReleaseGate)
  const foundation = buildFoundationBaseline(roadmap, hardeningStub)
  const hardeningSummary = summarizeProgressIssue(hardening)

  const data = {
    foundation,
    harness,
    hardening,
    hardeningSummary
  }

  replaceGeneratedSection(
    PROGRESS_DOC,
    PROGRESS_START,
    PROGRESS_END,
    buildProgressBlock(data)
  )
  replaceGeneratedSection(VISION_DOC, VISION_START, VISION_END, buildVisionBlock(data))
  process.stdout.write(`[docs] tracker docs synced from ${issueReader.sourceLabel}\n`)
}

main()
