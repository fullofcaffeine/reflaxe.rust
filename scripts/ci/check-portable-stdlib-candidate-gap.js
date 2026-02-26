#!/usr/bin/env node

const fs = require('fs')

const reportPath = 'docs/portable-stdlib-candidates.json'

function fail(message) {
  console.error(`[ci:guards] ERROR: ${message}`)
  process.exit(1)
}

function parseNonNegativeInt(raw, label) {
  if (raw == null || raw === '') {
    return null
  }
  if (!/^\d+$/.test(String(raw))) {
    fail(`${label} must be a non-negative integer, got: ${raw}`)
  }
  return Number(raw)
}

function parseArgs(argv) {
  let maxGap = null
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--max-gap') {
      maxGap = parseNonNegativeInt(argv[i + 1], '--max-gap')
      i += 1
      continue
    }
    if (arg === '-h' || arg === '--help') {
      console.log(`Usage: node scripts/ci/check-portable-stdlib-candidate-gap.js [--max-gap <n>]

Checks docs/portable-stdlib-candidates.json and fails when missingFromTier2 exceeds the
configured budget.

Budget resolution order:
  1) --max-gap <n>
  2) PORTABLE_STDLIB_CANDIDATE_GAP_MAX
  3) default 0
`)
      process.exit(0)
    }
    fail(`unknown argument: ${arg}`)
  }
  return { maxGap }
}

function resolveMaxGap(cliMaxGap) {
  if (cliMaxGap != null) {
    return cliMaxGap
  }
  const envMax = parseNonNegativeInt(
    process.env.PORTABLE_STDLIB_CANDIDATE_GAP_MAX,
    'PORTABLE_STDLIB_CANDIDATE_GAP_MAX'
  )
  if (envMax != null) {
    return envMax
  }
  return 0
}

if (!fs.existsSync(reportPath)) {
  fail(`missing report artifact: ${reportPath}. Run: npm run stdlib:audit:candidates`)
}

let report = null
try {
  report = JSON.parse(fs.readFileSync(reportPath, 'utf8'))
} catch (error) {
  fail(`invalid JSON in ${reportPath}: ${error}`)
}

if (report == null || typeof report !== 'object') {
  fail(`${reportPath} must contain a JSON object`)
}
if (!Array.isArray(report.missingFromTier2)) {
  fail(`${reportPath} must include missingFromTier2 array`)
}

const args = parseArgs(process.argv.slice(2))
const maxGap = resolveMaxGap(args.maxGap)
const missing = report.missingFromTier2
const missingCount = missing.length

if (missingCount > maxGap) {
  const preview = missing.slice(0, 20).map((moduleName) => `- ${moduleName}`)
  if (missing.length > 20) {
    preview.push(`- ... (${missing.length - 20} more)`)
  }
  fail(
    `portable stdlib candidate gap budget exceeded: missingFromTier2=${missingCount} > maxGap=${maxGap}\n${preview.join(
      '\n'
    )}`
  )
}

console.log(
  `[ci:guards] OK: portable stdlib candidate gap within budget (${missingCount} missing, max ${maxGap})`
)
