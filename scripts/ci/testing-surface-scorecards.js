#!/usr/bin/env node

/**
 * Why:
 * A green compiler test can otherwise be mistaken for proof about a different product surface,
 * such as no-hxrt packaging or Windows behavior. This checker keeps the claim boundaries explicit
 * and makes the example and feedback-ring inventory fail closed.
 *
 * What:
 * Validates `docs/testing-surface-scorecards.json` and generates the beginner-readable Markdown
 * projection. It deliberately does not select or skip tests; affected-test selection remains
 * observation-only until its independent backstop has enough evidence.
 *
 * How:
 * Run with `--check` in hooks/CI or `--write` after reviewing a scorecard change. Tests can pass an
 * alternate manifest and skip the generated-document comparison for focused negative mutations.
 */

const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const defaultManifest = path.join(repoRoot, 'docs', 'testing-surface-scorecards.json')
const generatedDoc = path.join(repoRoot, 'docs', 'testing-surface-scorecards.md')
const requiredSurfaceIds = [
  'portable-compiler',
  'representation-metal',
  'runtime',
  'no-hxrt',
  'diagnostics-source-maps',
  'cargo-package-platform'
]
const allowedStatuses = new Set(['satisfied', 'partial', 'absent', 'intentionally-inapplicable'])
const allowedExampleTiers = new Set(['flagship-application', 'capability-showcase', 'compile-only-snippet'])

function fail(message) {
  console.error(`[testing-surface-scorecards] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const options = { mode: 'check', manifest: defaultManifest, skipGeneratedDoc: false }
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === '--check') options.mode = 'check'
    else if (arg === '--write') options.mode = 'write'
    else if (arg === '--skip-generated-doc') options.skipGeneratedDoc = true
    else if (arg === '--manifest') {
      index += 1
      if (!argv[index]) fail('--manifest requires a path')
      options.manifest = path.resolve(argv[index])
    } else fail(`unknown argument: ${arg}`)
  }
  return options
}

function nonEmpty(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0) fail(`${label} must be a non-empty string`)
}

function unique(values, label) {
  const seen = new Set()
  for (const value of values) {
    if (seen.has(value)) fail(`${label} contains duplicate value: ${value}`)
    seen.add(value)
  }
}

function trackedExampleIds() {
  return fs.readdirSync(path.join(repoRoot, 'examples'), { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith('.'))
    .filter((entry) => fs.readdirSync(path.join(repoRoot, 'examples', entry.name))
      .some((file) => /^compile(?:\..+)?\.hxml$/.test(file)))
    .map((entry) => entry.name)
    .sort()
}

function validateOwner(owner, label) {
  if (!owner || typeof owner !== 'object') fail(`${label} must be an object`)
  nonEmpty(owner.path, `${label}.path`)
  nonEmpty(owner.command, `${label}.command`)
  if (!fs.existsSync(path.join(repoRoot, owner.path))) fail(`${label}.path does not exist: ${owner.path}`)
}

function validate(manifest) {
  if (manifest.schemaVersion !== 1 || manifest.contract !== 'haxe-rust-testing-surface-scorecards')
    fail('unsupported manifest schema or contract')

  if (!Array.isArray(manifest.surfaces)) fail('surfaces must be an array')
  const surfaceIds = manifest.surfaces.map((surface) => surface.id)
  unique(surfaceIds, 'surface IDs')
  for (const required of requiredSurfaceIds) {
    if (!surfaceIds.includes(required)) fail(`missing required product surface: ${required}`)
  }
  for (const surface of manifest.surfaces) {
    nonEmpty(surface.name, `${surface.id}.name`)
    if (!['applies', 'does-not-apply'].includes(surface.officialHaxeTargetQualification))
      fail(`${surface.id}.officialHaxeTargetQualification is invalid`)
    if (surface.id === 'portable-compiler') {
      if (surface.officialHaxeTargetQualification !== 'applies')
        fail('official Haxe target qualification must apply to portable-compiler')
    } else if (surface.officialHaxeTargetQualification !== 'does-not-apply') {
      fail('official Haxe target qualification applies only to portable-compiler')
    }
    for (const field of ['profiles', 'protectedClaims', 'focusedOwners', 'verticalOwners', 'examples', 'residualRisks']) {
      if (!Array.isArray(surface[field])) fail(`${surface.id}.${field} must be an array`)
    }
    if (surface.focusedOwners.length === 0) fail(`${surface.id} needs at least one focused owner`)
    if (surface.verticalOwners.length === 0) fail(`${surface.id} needs at least one vertical owner`)
    surface.focusedOwners.forEach((owner, index) => validateOwner(owner, `${surface.id}.focusedOwners[${index}]`))
    surface.verticalOwners.forEach((owner, index) => validateOwner(owner, `${surface.id}.verticalOwners[${index}]`))
    ;(surface.systemOwners || []).forEach((owner, index) => validateOwner(owner, `${surface.id}.systemOwners[${index}]`))
    nonEmpty(surface.fullBackstop, `${surface.id}.fullBackstop`)
    nonEmpty(surface.lastCleanProof, `${surface.id}.lastCleanProof`)
  }

  if (!Array.isArray(manifest.conclusionAudit)) fail('conclusionAudit must be an array')
  for (const entry of manifest.conclusionAudit) {
    nonEmpty(entry.conclusion, 'conclusionAudit.conclusion')
    if (!allowedStatuses.has(entry.status)) fail(`invalid conclusion status: ${entry.status}`)
    nonEmpty(entry.currentEvidence, `${entry.conclusion}.currentEvidence`)
  }

  if (!Array.isArray(manifest.feedbackRings)) fail('feedbackRings must be an array')
  const ringIds = manifest.feedbackRings.map((ring) => ring.id)
  if (JSON.stringify(ringIds) !== JSON.stringify(['R0', 'R1', 'R2', 'R3', 'R4', 'R5']))
    fail('feedback rings must be exactly R0 through R5 in order')
  for (const ring of manifest.feedbackRings) {
    for (const field of ['name', 'currentCommand', 'claim', 'selection', 'cacheRule'])
      nonEmpty(ring[field], `${ring.id}.${field}`)
  }

  if (!Array.isArray(manifest.examples)) fail('examples must be an array')
  const manifestExamples = manifest.examples.map((example) => example.id).sort()
  unique(manifestExamples, 'example IDs')
  if (JSON.stringify(manifestExamples) !== JSON.stringify(trackedExampleIds()))
    fail('example classification does not match examples/ directories containing compile HXML files')
  for (const example of manifest.examples) {
    if (!allowedExampleTiers.has(example.tier)) fail(`${example.id} has invalid example tier`)
    if (!Array.isArray(example.surfaces) || example.surfaces.length === 0) fail(`${example.id} must name a product surface`)
    if (!Array.isArray(example.observedLevels)) fail(`${example.id}.observedLevels must be an array`)
    for (const surface of example.surfaces) {
      if (!surfaceIds.includes(surface)) fail(`${example.id} refers to unknown surface: ${surface}`)
    }
    if (example.tier === 'flagship-application') {
      for (const level of ['compile', 'cargo-build', 'runtime']) {
        if (!example.observedLevels.includes(level))
          fail('flagship application must execute compile, cargo-build, and runtime')
      }
    }
    const requiredLevelsBySurface = {
      'portable-compiler': ['authored-haxe', 'compile', 'cargo-build'],
      'representation-metal': ['authored-haxe', 'compile', 'cargo-build'],
      runtime: ['runtime'],
      'no-hxrt': ['authored-haxe', 'compile', 'cargo-build', 'runtime'],
      'cargo-package-platform': ['cargo-build']
    }
    for (const surface of example.surfaces) {
      for (const level of requiredLevelsBySurface[surface] || []) {
        if (!example.observedLevels.includes(level))
          fail(`${example.id} cannot support ${surface} without observed level: ${level}`)
      }
    }
    if (example.surfaces.includes('no-hxrt')) {
      const exampleDir = path.join(repoRoot, 'examples', example.id)
      const compileFiles = fs.readdirSync(exampleDir).filter((file) => /^compile(?:\..+)?\.hxml$/.test(file))
      if (!compileFiles.some((file) => fs.readFileSync(path.join(exampleDir, file), 'utf8').includes('rust_no_hxrt')))
        fail(`${example.id} claims no-hxrt without a compile HXML that enables rust_no_hxrt`)
    }
  }
  for (const surface of manifest.surfaces) {
    for (const example of surface.examples) {
      const row = manifest.examples.find((candidate) => candidate.id === example)
      if (!row || !row.surfaces.includes(surface.id))
        fail(`${surface.id} example link is not reciprocal: ${example}`)
    }
  }

  const workflow = manifest.representativeWorkflow
  if (!workflow || typeof workflow !== 'object') fail('representativeWorkflow must be an object')
  if (!surfaceIds.includes(workflow.surface)) fail('representativeWorkflow has unknown surface')
  for (const field of ['preconditions', 'action', 'observableResult', 'edgeBehavior', 'protectedClaim'])
    nonEmpty(workflow.scenario && workflow.scenario[field], `representativeWorkflow.scenario.${field}`)
  for (const field of ['command', 'evidence', 'failure'])
    nonEmpty(workflow.redState && workflow.redState[field], `representativeWorkflow.redState.${field}`)
  if (!workflow.expectedResult || workflow.expectedResult.source === 'implementation-under-test')
    fail('expected result source must be independent of the implementation under test')
  for (const field of ['kind', 'source', 'independence'])
    nonEmpty(workflow.expectedResult[field], `representativeWorkflow.expectedResult.${field}`)
  const tracerLevels = workflow.tracerBullet && workflow.tracerBullet.observedLevels
  for (const level of ['authored-haxe', 'typed-decision', 'generated-rust', 'cargo-build', 'runtime']) {
    if (!Array.isArray(tracerLevels) || !tracerLevels.includes(level))
      fail(`representative tracer bullet is missing level: ${level}`)
  }
}

function escapeCell(value) {
  return String(value).replace(/\|/g, '\\|').replace(/\n/g, ' ')
}

function render(manifest) {
  const lines = [
    '# Testing Strategy and Product-Surface Scorecards',
    '',
    '> Generated from `docs/testing-surface-scorecards.json`. Run `npm run docs:sync:testing-scorecards` after reviewing the structured source.',
    '',
    'This page says what each test group can actually prove. A green result for one row does not make a different row green.',
    '',
    '## Incremental strategy audit',
    '',
    '| New conclusion | Current state | Concrete evidence or limit |',
    '| --- | --- | --- |'
  ]
  for (const entry of manifest.conclusionAudit)
    lines.push(`| ${escapeCell(entry.conclusion)} | ${entry.status} | ${escapeCell(entry.currentEvidence)} |`)

  lines.push('', '## Independent product surfaces', '',
    '| Surface | Status | Official Haxe qualification | Focused owners | Real vertical owners | Full backstop |',
    '| --- | --- | --- | ---: | ---: | --- |')
  for (const surface of manifest.surfaces) {
    lines.push(`| ${escapeCell(surface.name)} | ${surface.status} | ${surface.officialHaxeTargetQualification} | ${surface.focusedOwners.length} | ${surface.verticalOwners.length} | \`${escapeCell(surface.fullBackstop)}\` |`)
  }

  for (const surface of manifest.surfaces) {
    lines.push('', `### ${surface.name}`, '', '**Claims protected**', '')
    for (const claim of surface.protectedClaims) lines.push(`- ${claim}`)
    lines.push('', '**Focused owners**', '')
    for (const owner of surface.focusedOwners) lines.push(`- \`${owner.command}\` — ${owner.path}`)
    lines.push('', '**Real vertical owners**', '')
    for (const owner of surface.verticalOwners) lines.push(`- \`${owner.command}\` — ${owner.observer}`)
    if ((surface.systemOwners || []).length > 0) {
      lines.push('', '**Downstream or platform owners**', '')
      for (const owner of surface.systemOwners) lines.push(`- \`${owner.command}\` — ${owner.observer}`)
    }
    lines.push('', `Last clean proof: ${surface.lastCleanProof}.`, '', '**Remaining limits**', '')
    for (const risk of surface.residualRisks) lines.push(`- ${risk}`)
  }

  lines.push('', '## Feedback rings', '',
    '| Ring | Purpose | Current command/owner | Selection | Cache rule |',
    '| --- | --- | --- | --- | --- |')
  for (const ring of manifest.feedbackRings)
    lines.push(`| ${ring.id} | ${escapeCell(ring.name)} | ${escapeCell(ring.currentCommand)} | ${escapeCell(ring.selection)} | ${escapeCell(ring.cacheRule)} |`)

  lines.push('', '## Examples and the level they prove', '',
    '| Example | Tier | Product surfaces | Actually observed in CI |',
    '| --- | --- | --- | --- |')
  for (const example of manifest.examples)
    lines.push(`| \`examples/${example.id}\` | ${example.tier} | ${example.surfaces.join(', ')} | ${example.observedLevels.join(', ')} |`)

  const workflow = manifest.representativeWorkflow
  lines.push('', '## Representative behavior-first workflow', '', `### ${workflow.title}`, '',
    `Product surface: \`${workflow.surface}\`.`, '',
    `- Preconditions: ${workflow.scenario.preconditions}`,
    `- Action: ${workflow.scenario.action}`,
    `- Observable result: ${workflow.scenario.observableResult}`,
    `- Edge behavior: ${workflow.scenario.edgeBehavior}`,
    `- Protected claim: ${workflow.scenario.protectedClaim}`,
    '', '**Red state before the fix**', '',
    `- Command: \`${workflow.redState.command}\``,
    `- Failure: ${workflow.redState.failure}`,
    `- Durable record: ${workflow.redState.evidence}.`,
    '', '**Source of the expected result**', '',
    `- Kind: ${workflow.expectedResult.kind}.`,
    `- Source: ${workflow.expectedResult.source}.`,
    `- Independence: ${workflow.expectedResult.independence}`,
    '', '**First real vertical path**', '',
    `- Fixture: \`${workflow.tracerBullet.fixture}\``,
    `- Command: \`${workflow.tracerBullet.command}\``,
    `- Observed levels: ${workflow.tracerBullet.observedLevels.join(' -> ')}.`,
    `- Result: ${workflow.tracerBullet.result}`,
    '', '**Broader proof**', '',
    `- Command: \`${workflow.broaderProof.command}\``,
    `- Result: ${workflow.broaderProof.result}`,
    `- Durable record: ${workflow.broaderProof.evidence}.`)

  lines.push('', '## Expected-result and review rules', '',
    'Expected results must come from a specification, a manually written minimal expectation, a pinned comparison implementation, an invariant, a reviewed generated file, or real consumer behavior. The emitter must not generate its own expected answer.',
    '', 'For representation, runtime, ABI, package, security, migration, source-location, or public-claim changes, a review pass separate from implementation must answer:', '')
  for (const item of manifest.highRiskReviewChecklist) lines.push(`- ${item}`)
  lines.push('', '## Retries and quarantine', '',
    `- Product test retries: ${manifest.retryPolicy.productTestRetries}.`,
    `- Network retries: ${manifest.retryPolicy.networkBootstrapRetries}.`,
    `- Quarantine: ${manifest.retryPolicy.quarantine}`,
    `- Current quarantines: ${manifest.retryPolicy.currentQuarantines.length}.`,
    '', '## Portfolio interpretation', '', manifest.portfolioGuidance.interpretation, '', manifest.portfolioGuidance.note)
  return `${lines.join('\n')}\n`
}

const options = parseArgs(process.argv.slice(2))
if (!fs.existsSync(options.manifest)) fail(`manifest not found: ${options.manifest}`)
let manifest
try {
  manifest = JSON.parse(fs.readFileSync(options.manifest, 'utf8'))
} catch (error) {
  fail(`cannot parse manifest: ${error.message}`)
}
validate(manifest)

const markdown = render(manifest)
if (!options.skipGeneratedDoc && options.manifest === defaultManifest) {
  if (options.mode === 'write') {
    fs.writeFileSync(generatedDoc, markdown)
  } else if (!fs.existsSync(generatedDoc) || fs.readFileSync(generatedDoc, 'utf8') !== markdown) {
    fail('generated scorecard Markdown is stale; run npm run docs:sync:testing-scorecards')
  }
}

console.log(`[testing-surface-scorecards] OK: ${manifest.surfaces.length} independent surfaces, ${manifest.examples.length} classified examples, ${manifest.feedbackRings.length} feedback rings`)
