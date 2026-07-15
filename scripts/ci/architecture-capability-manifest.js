#!/usr/bin/env node

/**
 * Why:
 * Product-level statements about GC, ownership, Rust interop, stdlib support, output quality, and
 * maturity are easy to overread when they are maintained as prose across several entrypoints. This
 * guard gives those statements one structured owner and prevents a narrow implemented mechanism
 * from silently becoming a blanket Haxe-to-Rust claim.
 *
 * What:
 * Validate `docs/architecture-capability-manifest.json`, render the full human review page, and
 * synchronize compact generated summaries in README and the FAQ. The manifest references existing
 * executable and generated evidence; it does not copy operation inventories or test counts owned by
 * other contracts.
 *
 * How:
 * - Require the objection/claim categories that define this architecture boundary.
 * - Enforce status-specific evidence, qualification, ownership, and blocking-Bead rules.
 * - Resolve every evidence path, npm command, and Bead reference against repository authorities.
 * - Render deterministic Markdown without timestamps, host paths, or mutable CI results.
 * - Compare generated consumers byte-for-byte in check mode.
 */

const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const defaultManifestPath = path.join(repoRoot, 'docs', 'architecture-capability-manifest.json')
const defaultPagePath = path.join(repoRoot, 'docs', 'architecture-capability.md')
const defaultReadmePath = path.join(repoRoot, 'README.md')
const defaultFaqPath = path.join(repoRoot, 'docs', 'faq.md')
const beadsExportPath = path.join(repoRoot, '.beads', 'issues.jsonl')
const packagePath = path.join(repoRoot, 'package.json')

const beginMarker = '<!-- BEGIN GENERATED ARCHITECTURE CAPABILITY SUMMARY -->'
const endMarker = '<!-- END GENERATED ARCHITECTURE CAPABILITY SUMMARY -->'

const allowedStatuses = new Set(['closed', 'qualified', 'open'])
const allowedEvidenceClasses = new Set(['executable', 'generated', 'documentary', 'independent'])
const requiredClaimIds = [
  'memory.no-universal-tracing-gc',
  'memory.portable-reference-semantics',
  'runtime.fail-closed-no-hxrt',
  'ownership.no-duplicate-rust-borrow-checker',
  'ownership.scoped-borrow-safety',
  'interop.lifetime-islands',
  'interop.typed-rust-crates',
  'stdlib.portable-contract',
  'output.handwritten-rust-quality',
  'maturity.bounded-production',
  'maturity.unqualified-objection-closure'
]
const requiredObjectionIds = [
  'gc-required',
  'runtime-interop-friction',
  'duplicate-borrow-checker',
  'lifetime-annotated-source-and-stdlib'
]

function parseArgs(argv) {
  const args = {
    mode: 'check',
    modeExplicit: false,
    manifestPath: defaultManifestPath,
    pagePath: defaultPagePath,
    readmePath: defaultReadmePath,
    faqPath: defaultFaqPath
  }

  function setMode(mode) {
    if (args.modeExplicit) throw new Error('use only one of --check, --write, or --validate-only')
    args.mode = mode
    args.modeExplicit = true
  }

  function nextPath(index, flag) {
    if (index + 1 >= argv.length) throw new Error(`${flag} requires a path`)
    return path.resolve(repoRoot, argv[index + 1])
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === '--check') {
      setMode('check')
    } else if (arg === '--write') {
      setMode('write')
    } else if (arg === '--validate-only') {
      setMode('validate')
    } else if (arg === '--manifest') {
      args.manifestPath = nextPath(index, arg)
      index += 1
    } else if (arg === '--page') {
      args.pagePath = nextPath(index, arg)
      index += 1
    } else if (arg === '--readme') {
      args.readmePath = nextPath(index, arg)
      index += 1
    } else if (arg === '--faq') {
      args.faqPath = nextPath(index, arg)
      index += 1
    } else {
      throw new Error(`unknown argument: ${arg}`)
    }
  }
  return args
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function readBeadIds(errors) {
  if (!fs.existsSync(beadsExportPath)) {
    errors.push('missing Beads export: .beads/issues.jsonl')
    return new Set()
  }
  const ids = new Set()
  for (const [index, line] of fs.readFileSync(beadsExportPath, 'utf8').split(/\r?\n/).entries()) {
    if (line.trim().length === 0) continue
    try {
      const record = JSON.parse(line)
      if (record && record._type === 'issue' && typeof record.id === 'string') ids.add(record.id)
    } catch (error) {
      errors.push(`invalid Beads export JSON on line ${index + 1}: ${error.message}`)
    }
  }
  return ids
}

function requireString(value, label, errors) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    errors.push(`${label} must be a non-empty string`)
    return ''
  }
  return value
}

function requireStringArray(value, label, errors, allowEmpty = false) {
  if (!Array.isArray(value)) {
    errors.push(`${label} must be an array`)
    return []
  }
  if (!allowEmpty && value.length === 0) errors.push(`${label} must contain at least one entry`)
  for (const item of value) {
    if (typeof item !== 'string' || item.trim().length === 0) {
      errors.push(`${label} contains an empty or non-string entry`)
    }
  }
  return value.filter((item) => typeof item === 'string' && item.trim().length > 0)
}

function checkUnique(values, label, errors) {
  const seen = new Set()
  for (const value of values) {
    if (seen.has(value)) errors.push(`duplicate ${label}: ${value}`)
    seen.add(value)
  }
}

function containsLocalPath(value) {
  return /(?:\/Users\/|\/home\/[^/]+\/|[A-Za-z]:\\Users\\)/.test(value)
}

function validateManifest(manifest, rawText = '') {
  const errors = []
  if (manifest == null || typeof manifest !== 'object' || Array.isArray(manifest)) {
    return ['manifest must contain a JSON object']
  }
  if (manifest.schemaVersion !== 1) errors.push('manifest.schemaVersion must be 1')
  if (manifest.contract !== 'architecture-capability-claims') {
    errors.push('manifest.contract must be architecture-capability-claims')
  }
  if (containsLocalPath(rawText)) errors.push('manifest must not contain machine-local absolute paths')

  const publicAnswer = manifest.publicAnswer
  if (publicAnswer == null || typeof publicAnswer !== 'object' || Array.isArray(publicAnswer)) {
    errors.push('manifest.publicAnswer must be an object')
  } else {
    for (const field of ['headline', 'allowed', 'notAllowed', 'upgradeGate', 'releaseBoundary']) {
      requireString(publicAnswer[field], `manifest.publicAnswer.${field}`, errors)
    }
  }

  const evidence = Array.isArray(manifest.evidence) ? manifest.evidence : []
  if (!Array.isArray(manifest.evidence)) errors.push('manifest.evidence must be an array')
  const evidenceById = new Map()
  const packageScripts = readJson(packagePath).scripts || {}
  for (const [index, entry] of evidence.entries()) {
    const label = `manifest.evidence[${index}]`
    if (entry == null || typeof entry !== 'object' || Array.isArray(entry)) {
      errors.push(`${label} must be an object`)
      continue
    }
    const id = requireString(entry.id, `${label}.id`, errors)
    requireString(entry.label, `${label}.label`, errors)
    requireString(entry.description, `${label}.description`, errors)
    if (!allowedEvidenceClasses.has(entry.evidenceClass)) {
      errors.push(`${id || label} has invalid evidenceClass: ${entry.evidenceClass}`)
    }
    const paths = requireStringArray(entry.paths, `${id || label}.paths`, errors)
    const commands = requireStringArray(entry.commands, `${id || label}.commands`, errors, true)
    if (entry.evidenceClass === 'executable' && commands.length === 0) {
      errors.push(`${id || label} executable evidence must declare at least one command`)
    }
    if (evidenceById.has(id)) errors.push(`duplicate evidence id: ${id}`)
    else if (id.length > 0) evidenceById.set(id, entry)

    for (const evidencePath of paths) {
      if (path.isAbsolute(evidencePath)) {
        errors.push(`${id || label} evidence paths must be repository-relative: ${evidencePath}`)
      } else if (!fs.existsSync(path.join(repoRoot, evidencePath))) {
        errors.push(`${id || label} has missing evidence path: ${evidencePath}`)
      }
    }
    for (const command of commands) {
      if (containsLocalPath(command)) errors.push(`${id || label} command contains a machine-local path`)
      const npmMatch = command.match(/^npm run ([^\s]+)(?:\s|$)/)
      if (npmMatch && typeof packageScripts[npmMatch[1]] !== 'string') {
        errors.push(`${id || label} references unknown npm script: ${npmMatch[1]}`)
      }
    }
  }
  checkUnique(evidence.map((entry) => entry && entry.id).filter(Boolean), 'evidence id', errors)

  const claims = Array.isArray(manifest.claims) ? manifest.claims : []
  if (!Array.isArray(manifest.claims)) errors.push('manifest.claims must be an array')
  const claimById = new Map()
  const beadIds = readBeadIds(errors)
  for (const [index, claim] of claims.entries()) {
    const label = `manifest.claims[${index}]`
    if (claim == null || typeof claim !== 'object' || Array.isArray(claim)) {
      errors.push(`${label} must be an object`)
      continue
    }
    const id = requireString(claim.id, `${label}.id`, errors)
    if (claimById.has(id)) errors.push(`duplicate claim id: ${id}`)
    else if (id.length > 0) claimById.set(id, claim)
    requireString(claim.question, `${id || label}.question`, errors)
    requireString(claim.verdict, `${id || label}.verdict`, errors)
    if (!allowedStatuses.has(claim.status)) errors.push(`${id || label} has invalid status: ${claim.status}`)

    const objectionIds = requireStringArray(claim.objectionIds, `${id || label}.objectionIds`, errors)
    const mechanisms = requireStringArray(claim.mechanisms, `${id || label}.mechanisms`, errors)
    const counterexamples = requireStringArray(claim.counterexamples, `${id || label}.counterexamples`, errors)
    const evidenceIds = requireStringArray(claim.evidenceIds, `${id || label}.evidenceIds`, errors)
    const qualifications = requireStringArray(claim.qualifications, `${id || label}.qualifications`, errors, true)
    const doesNotMean = requireStringArray(claim.doesNotMean, `${id || label}.doesNotMean`, errors)
    const ownerBeads = requireStringArray(claim.ownerBeads, `${id || label}.ownerBeads`, errors)
    const blockingBeads = requireStringArray(claim.blockingBeads, `${id || label}.blockingBeads`, errors, true)
    const remainingGapBeads = requireStringArray(claim.remainingGapBeads, `${id || label}.remainingGapBeads`, errors, true)

    for (const evidenceId of evidenceIds) {
      if (!evidenceById.has(evidenceId)) errors.push(`${id || label} references unknown evidence: ${evidenceId}`)
    }
    for (const beadId of [...ownerBeads, ...blockingBeads, ...remainingGapBeads]) {
      if (!beadIds.has(beadId)) errors.push(`${id || label} references unknown Bead: ${beadId}`)
    }

    if (claim.status === 'closed') {
      if (qualifications.length > 0) errors.push(`closed claim ${id} cannot retain qualifications`)
      if (blockingBeads.length > 0) errors.push(`closed claim ${id} cannot retain blockingBeads`)
      const hasExecutableEvidence = evidenceIds.some(
        (evidenceId) => evidenceById.get(evidenceId)?.evidenceClass === 'executable'
      )
      if (!hasExecutableEvidence) errors.push(`closed claim ${id} must cite executable evidence`)
    }
    if (claim.status === 'qualified') {
      if (qualifications.length === 0) errors.push(`qualified claim ${id} must state at least one qualification`)
      if (ownerBeads.length === 0) errors.push(`qualified claim ${id} must declare ownerBeads`)
      if (remainingGapBeads.length === 0) errors.push(`qualified claim ${id} must declare remainingGapBeads`)
    }
    if (claim.status === 'open' && blockingBeads.length === 0) {
      errors.push(`open claim ${id} must declare blockingBeads`)
    }
    checkUnique(objectionIds, `${id} objection id`, errors)
    checkUnique(mechanisms, `${id} mechanism`, errors)
    checkUnique(counterexamples, `${id} counterexample`, errors)
    checkUnique(evidenceIds, `${id} evidence id`, errors)
  }

  for (const requiredId of requiredClaimIds) {
    if (!claimById.has(requiredId)) errors.push(`missing required claim: ${requiredId}`)
  }

  const objections = Array.isArray(manifest.objections) ? manifest.objections : []
  if (!Array.isArray(manifest.objections)) errors.push('manifest.objections must be an array')
  const objectionById = new Map()
  const claimsMappedFromObjections = new Set()
  for (const [index, objection] of objections.entries()) {
    const label = `manifest.objections[${index}]`
    if (objection == null || typeof objection !== 'object' || Array.isArray(objection)) {
      errors.push(`${label} must be an object`)
      continue
    }
    const id = requireString(objection.id, `${label}.id`, errors)
    requireString(objection.statement, `${id || label}.statement`, errors)
    const claimIds = requireStringArray(objection.claimIds, `objection ${id || label}.claimIds`, errors)
    if (objectionById.has(id)) errors.push(`duplicate objection id: ${id}`)
    else if (id.length > 0) objectionById.set(id, objection)
    for (const claimId of claimIds) {
      claimsMappedFromObjections.add(claimId)
      if (!claimById.has(claimId)) errors.push(`objection ${id} references unknown claim: ${claimId}`)
    }
  }
  for (const requiredId of requiredObjectionIds) {
    if (!objectionById.has(requiredId)) errors.push(`missing required objection: ${requiredId}`)
  }
  for (const claim of claims) {
    if (claim && typeof claim.id === 'string' && !claimsMappedFromObjections.has(claim.id)) {
      errors.push(`claim ${claim.id} is not mapped from an objection`)
    }
    for (const objectionId of claim?.objectionIds || []) {
      const objection = objectionById.get(objectionId)
      if (!objection) errors.push(`claim ${claim.id} references unknown objection: ${objectionId}`)
      else if (!objection.claimIds.includes(claim.id)) {
        errors.push(`claim ${claim.id} and objection ${objectionId} mapping is not bidirectional`)
      }
    }
  }

  return errors
}

function statusCounts(manifest) {
  const counts = { closed: 0, qualified: 0, open: 0 }
  for (const claim of manifest.claims) counts[claim.status] += 1
  return counts
}

function inlineCodeList(values) {
  return values.map((value) => `\`${value}\``).join(', ')
}

function evidenceLink(evidencePath) {
  const target = evidencePath.startsWith('docs/') ? evidencePath.slice('docs/'.length) : `../${evidencePath}`
  return `[\`${evidencePath}\`](${target})`
}

function renderBulletSection(lines, title, values) {
  lines.push(`- ${title}:`)
  for (const value of values) lines.push(`  - ${value}`)
}

function objectionDisposition(objection, claimById) {
  const statuses = objection.claimIds.map((id) => claimById.get(id).status)
  const hasClosed = statuses.includes('closed')
  const hasQualified = statuses.includes('qualified')
  const hasOpen = statuses.includes('open')
  if (hasClosed && hasOpen) return 'Refuted as a necessity; broad closure open'
  if (hasClosed && hasQualified) return 'Refuted as a necessity; qualifications remain'
  if (hasClosed) return 'Refuted as a necessity'
  if (hasOpen) return 'Open'
  return 'Qualified'
}

function titleStatus(status) {
  return `${status[0].toUpperCase()}${status.slice(1)}`
}

function escapeTable(value) {
  return value.replaceAll('|', '\\|').replaceAll('\n', ' ')
}

function renderPage(manifest) {
  const lines = []
  const counts = statusCounts(manifest)
  const evidenceById = new Map(manifest.evidence.map((entry) => [entry.id, entry]))
  const claimById = new Map(manifest.claims.map((claim) => [claim.id, claim]))

  lines.push('# Architecture Capability Claims')
  lines.push('')
  lines.push('This page is generated deterministically from [`architecture-capability-manifest.json`](architecture-capability-manifest.json).')
  lines.push('')
  lines.push('## Why')
  lines.push('')
  lines.push('The old Haxe-to-Rust impossibility argument combines several different questions: whether a tracing GC is mandatory, whether portable Haxe references can coexist with Rust ownership, whether Rust interop must cross a runtime, and whether Haxe must reproduce Rust lifetime syntax. Each exact claim needs its own evidence and boundary.')
  lines.push('')
  lines.push('## What')
  lines.push('')
  lines.push(manifest.publicAnswer.headline)
  lines.push('')
  lines.push(`Current classification: **${counts.closed} closed**, **${counts.qualified} qualified**, and **${counts.open} open**.`)
  lines.push('')
  lines.push('A closed status proves only the exact claim stated below. Qualified means the mechanism works inside explicit exclusions. Open means the public statement is blocked even if narrower components already work.')
  lines.push('')
  lines.push('## How')
  lines.push('')
  lines.push('- Existing compatibility, semantic-confidence, lifecycle, policy, output, performance, and consumer evidence stays owned by its current contract.')
  lines.push('- This manifest references those authorities instead of duplicating their operation lists, counts, or current CI results.')
  lines.push('- Status changes fail closed unless the claim retains the evidence and ownership required for its new classification.')
  lines.push('- README and FAQ carry generated summaries, so their headline cannot drift independently.')
  lines.push('')
  lines.push('## What You Can Say Today')
  lines.push('')
  lines.push(`> ${manifest.publicAnswer.allowed}`)
  lines.push('')
  lines.push(`Do not claim: ${manifest.publicAnswer.notAllowed}`)
  lines.push('')
  lines.push(`Upgrade gate: ${manifest.publicAnswer.upgradeGate}`)
  lines.push('')
  lines.push(`Release boundary: ${manifest.publicAnswer.releaseBoundary}`)
  lines.push('')
  lines.push('This manifest **does not authorize stable 1.0** and is independent from the stable-major release gate.')
  lines.push('')
  lines.push('## Original Objection Map')
  lines.push('')
  lines.push('| Objection | Current disposition | Owning claims |')
  lines.push('| --- | --- | --- |')
  for (const objection of manifest.objections) {
    const disposition = objectionDisposition(objection, claimById)
    lines.push(`| ${escapeTable(objection.statement)} | **${titleStatus(disposition)}** | ${inlineCodeList(objection.claimIds)} |`)
  }
  lines.push('')
  lines.push('## Claim Review')
  lines.push('')

  for (const claim of manifest.claims) {
    lines.push(`### ${claim.id}`)
    lines.push('')
    lines.push(`- Status: **${titleStatus(claim.status)}**`)
    lines.push(`- Question: ${claim.question}`)
    lines.push(`- Verdict: ${claim.verdict}`)
    lines.push(`- Maps objections: ${inlineCodeList(claim.objectionIds)}`)
    renderBulletSection(lines, 'Mechanisms', claim.mechanisms)
    renderBulletSection(lines, 'Concrete counterexamples to the impossibility argument', claim.counterexamples)
    lines.push('- Evidence:')
    for (const evidenceId of claim.evidenceIds) {
      const evidence = evidenceById.get(evidenceId)
      lines.push(`  - \`${evidenceId}\` (${evidence.evidenceClass}): ${evidence.description}`)
    }
    if (claim.qualifications.length > 0) renderBulletSection(lines, 'Qualifications', claim.qualifications)
    else lines.push('- Qualifications: none for this exact narrow claim.')
    renderBulletSection(lines, 'Does not mean', claim.doesNotMean)
    lines.push(`- Owner Beads: ${inlineCodeList(claim.ownerBeads)}`)
    lines.push(`- Blocking Beads: ${claim.blockingBeads.length > 0 ? inlineCodeList(claim.blockingBeads) : 'none'}`)
    lines.push(`- Remaining-gap Beads: ${claim.remainingGapBeads.length > 0 ? inlineCodeList(claim.remainingGapBeads) : 'none'}`)
    lines.push('')
  }

  lines.push('## Evidence Registry')
  lines.push('')
  lines.push('The registry names evidence authorities; it intentionally does not copy their changing counts or detailed inventories.')
  lines.push('')
  for (const evidence of manifest.evidence) {
    lines.push(`### ${evidence.id}`)
    lines.push('')
    lines.push(`- Class: \`${evidence.evidenceClass}\``)
    lines.push(`- Purpose: ${evidence.description}`)
    lines.push(`- Paths: ${evidence.paths.map(evidenceLink).join(', ')}`)
    lines.push(`- Commands: ${evidence.commands.length > 0 ? inlineCodeList(evidence.commands) : 'none (documentary authority)'}`)
    lines.push('')
  }

  lines.push('## Status Change Rules')
  lines.push('')
  lines.push('- `closed`: the exact claim cites executable evidence and has no qualification or blocker hidden in its wording.')
  lines.push('- `qualified`: exact exclusions, an owner, and remaining-gap Beads are mandatory.')
  lines.push('- `open`: at least one blocking Bead is mandatory.')
  lines.push('- Final broad authorization remains owned by `haxe.rust-oo3.98.10`, not by a green generator run.')
  return lines.join('\n')
}

function renderSummary(manifest, linkTarget) {
  const counts = statusCounts(manifest)
  return [
    beginMarker,
    `Architecture-claim status: **${counts.closed} closed**, **${counts.qualified} qualified**, **${counts.open} open**.`,
    manifest.publicAnswer.headline,
    `Review the exact evidence, exclusions, and blocking Beads in the [generated architecture capability claims](${linkTarget}); this summary does not authorize stable 1.0 or an unqualified “all Haxe to handwritten-quality Rust” claim.`,
    endMarker
  ].join('\n')
}

function replaceGeneratedBlock(source, renderedBlock, label) {
  const beginIndex = source.indexOf(beginMarker)
  const endIndex = source.indexOf(endMarker)
  if (beginIndex < 0 || endIndex < beginIndex) throw new Error(`${label} is missing architecture capability summary markers`)
  if (source.indexOf(beginMarker, beginIndex + beginMarker.length) >= 0 || source.indexOf(endMarker, endIndex + endMarker.length) >= 0) {
    throw new Error(`${label} contains duplicate architecture capability summary markers`)
  }
  return `${source.slice(0, beginIndex)}${renderedBlock}${source.slice(endIndex + endMarker.length)}`
}

function buildArtifacts(manifest, args) {
  const pageText = `${renderPage(manifest)}\n`
  const readmeSource = fs.readFileSync(args.readmePath, 'utf8')
  const faqSource = fs.readFileSync(args.faqPath, 'utf8')
  const readmeText = replaceGeneratedBlock(readmeSource, renderSummary(manifest, 'docs/architecture-capability.md'), 'README')
  const faqText = replaceGeneratedBlock(faqSource, renderSummary(manifest, 'architecture-capability.md'), 'FAQ')
  return { pageText, readmeText, faqText }
}

function writeArtifacts(args, artifacts) {
  fs.mkdirSync(path.dirname(args.pagePath), { recursive: true })
  fs.writeFileSync(args.pagePath, artifacts.pageText)
  fs.writeFileSync(args.readmePath, artifacts.readmeText)
  fs.writeFileSync(args.faqPath, artifacts.faqText)
}

function checkArtifacts(args, artifacts) {
  const errors = []
  if (!fs.existsSync(args.pagePath) || fs.readFileSync(args.pagePath, 'utf8') !== artifacts.pageText) {
    errors.push('generated architecture capability page is stale; run npm run docs:sync:architecture-capability')
  }
  if (fs.readFileSync(args.readmePath, 'utf8') !== artifacts.readmeText) {
    errors.push('README architecture capability summary is stale; run npm run docs:sync:architecture-capability')
  }
  if (fs.readFileSync(args.faqPath, 'utf8') !== artifacts.faqText) {
    errors.push('FAQ architecture capability summary is stale; run npm run docs:sync:architecture-capability')
  }
  return errors
}

function main() {
  let args
  try {
    args = parseArgs(process.argv.slice(2))
  } catch (error) {
    console.error(`[architecture-capability] ERROR: ${error.message}`)
    process.exit(1)
  }

  let rawText
  let manifest
  try {
    rawText = fs.readFileSync(args.manifestPath, 'utf8')
    manifest = JSON.parse(rawText)
  } catch (error) {
    console.error(`[architecture-capability] ERROR: cannot read manifest: ${error.message}`)
    process.exit(1)
  }

  const errors = validateManifest(manifest, rawText)
  if (errors.length > 0) {
    for (const error of errors) console.error(`[architecture-capability] ERROR: ${error}`)
    process.exit(1)
  }
  if (args.mode === 'validate') {
    console.log('[architecture-capability] manifest is valid')
    return
  }

  let artifacts
  try {
    artifacts = buildArtifacts(manifest, args)
  } catch (error) {
    console.error(`[architecture-capability] ERROR: ${error.message}`)
    process.exit(1)
  }

  if (args.mode === 'write') {
    writeArtifacts(args, artifacts)
    console.log('[architecture-capability] wrote generated page and entrypoint summaries')
    return
  }

  const artifactErrors = checkArtifacts(args, artifacts)
  if (artifactErrors.length > 0) {
    for (const error of artifactErrors) console.error(`[architecture-capability] ERROR: ${error}`)
    process.exit(1)
  }
  console.log('[architecture-capability] OK')
}

if (require.main === module) main()

module.exports = {
  beginMarker,
  endMarker,
  parseArgs,
  renderPage,
  renderSummary,
  validateManifest
}
