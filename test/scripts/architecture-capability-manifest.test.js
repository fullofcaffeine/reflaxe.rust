#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const checker = path.join(repoRoot, 'scripts', 'ci', 'architecture-capability-manifest.js')
const manifestPath = path.join(repoRoot, 'docs', 'architecture-capability-manifest.json')
const pagePath = path.join(repoRoot, 'docs', 'architecture-capability.md')
const readmePath = path.join(repoRoot, 'README.md')
const faqPath = path.join(repoRoot, 'docs', 'faq.md')

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

function run(args = []) {
  return cp.spawnSync(process.execPath, [checker, ...args], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`)
}

function expectFailure(result, pattern) {
  assert.notStrictEqual(result.status, 0, 'architecture capability guard unexpectedly succeeded')
  assert.match(`${result.stdout}\n${result.stderr}`, pattern)
}

function replaceGeneratedBlock(source, replacement) {
  const start = '<!-- BEGIN GENERATED ARCHITECTURE CAPABILITY SUMMARY -->'
  const end = '<!-- END GENERATED ARCHITECTURE CAPABILITY SUMMARY -->'
  const beginIndex = source.indexOf(start)
  const endIndex = source.indexOf(end)
  assert(beginIndex >= 0 && endIndex > beginIndex, 'entrypoint must contain architecture summary markers')
  return `${source.slice(0, beginIndex)}${start}\n${replacement}\n${end}${source.slice(endIndex + end.length)}`
}

function main() {
  assert(fs.existsSync(checker), 'architecture capability guard must exist')
  assert(fs.existsSync(manifestPath), 'architecture capability manifest must exist')
  assert(fs.existsSync(pagePath), 'generated architecture capability page must exist')

  const baseline = run(['--check'])
  assert.strictEqual(baseline.status, 0, baseline.stderr || baseline.stdout)

  const canonical = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  assert.strictEqual(canonical.schemaVersion, 1)
  assert.strictEqual(canonical.contract, 'architecture-capability-claims')
  assert.deepStrictEqual(canonical.claims.map((claim) => claim.id).sort(), requiredClaimIds.slice().sort())
  assert.deepStrictEqual(new Set(canonical.claims.map((claim) => claim.status)), new Set(['closed', 'qualified', 'open']))

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-architecture-capability-'))
  try {
    const missingClaim = structuredClone(canonical)
    const removedClaim = missingClaim.claims.shift()
    const missingClaimPath = path.join(root, 'missing-claim.json')
    writeJson(missingClaimPath, missingClaim)
    expectFailure(
      run(['--manifest', missingClaimPath, '--validate-only']),
      new RegExp(`missing required claim.*${removedClaim.id.replaceAll('.', '\\.')}`)
    )

    const invalidStatus = structuredClone(canonical)
    invalidStatus.claims[0].status = 'mostly-closed'
    const invalidStatusPath = path.join(root, 'invalid-status.json')
    writeJson(invalidStatusPath, invalidStatus)
    expectFailure(run(['--manifest', invalidStatusPath, '--validate-only']), /invalid status/)

    const invalidPromotion = structuredClone(canonical)
    invalidPromotion.claims.find((claim) => claim.status === 'qualified').status = 'closed'
    const invalidPromotionPath = path.join(root, 'invalid-promotion.json')
    writeJson(invalidPromotionPath, invalidPromotion)
    expectFailure(
      run(['--manifest', invalidPromotionPath, '--validate-only']),
      /closed claim.*cannot retain qualifications/
    )

    const unknownEvidence = structuredClone(canonical)
    unknownEvidence.claims[0].evidenceIds = ['evidence:not-registered']
    const unknownEvidencePath = path.join(root, 'unknown-evidence.json')
    writeJson(unknownEvidencePath, unknownEvidence)
    expectFailure(run(['--manifest', unknownEvidencePath, '--validate-only']), /unknown evidence/)

    const closedWithoutExecutableEvidence = structuredClone(canonical)
    const closedClaim = closedWithoutExecutableEvidence.claims.find((claim) => claim.status === 'closed')
    const documentaryEvidence = closedWithoutExecutableEvidence.evidence.find((entry) => entry.evidenceClass !== 'executable')
    assert(closedClaim && documentaryEvidence, 'canonical manifest needs closed claims and documentary evidence')
    closedClaim.evidenceIds = [documentaryEvidence.id]
    const closedWithoutExecutableEvidencePath = path.join(root, 'closed-without-executable-evidence.json')
    writeJson(closedWithoutExecutableEvidencePath, closedWithoutExecutableEvidence)
    expectFailure(
      run(['--manifest', closedWithoutExecutableEvidencePath, '--validate-only']),
      /closed claim.*executable evidence/
    )

    const unqualified = structuredClone(canonical)
    const qualifiedClaim = unqualified.claims.find((claim) => claim.status === 'qualified')
    assert(qualifiedClaim, 'canonical manifest needs a qualified claim')
    qualifiedClaim.qualifications = []
    const unqualifiedPath = path.join(root, 'unqualified.json')
    writeJson(unqualifiedPath, unqualified)
    expectFailure(run(['--manifest', unqualifiedPath, '--validate-only']), /qualified claim.*qualification/)

    const unownedQualification = structuredClone(canonical)
    unownedQualification.claims.find((claim) => claim.status === 'qualified').ownerBeads = []
    const unownedQualificationPath = path.join(root, 'unowned-qualification.json')
    writeJson(unownedQualificationPath, unownedQualification)
    expectFailure(run(['--manifest', unownedQualificationPath, '--validate-only']), /qualified claim.*ownerBeads/)

    const openWithoutBlocker = structuredClone(canonical)
    const openClaim = openWithoutBlocker.claims.find((claim) => claim.status === 'open')
    assert(openClaim, 'canonical manifest needs an open claim')
    openClaim.blockingBeads = []
    const openWithoutBlockerPath = path.join(root, 'open-without-blocker.json')
    writeJson(openWithoutBlockerPath, openWithoutBlocker)
    expectFailure(run(['--manifest', openWithoutBlockerPath, '--validate-only']), /open claim.*blockingBeads/)

    const missingEvidencePath = structuredClone(canonical)
    missingEvidencePath.evidence[0].paths = ['docs/not-a-real-evidence-artifact.md']
    const missingEvidenceArtifactPath = path.join(root, 'missing-evidence-path.json')
    writeJson(missingEvidenceArtifactPath, missingEvidencePath)
    expectFailure(run(['--manifest', missingEvidenceArtifactPath, '--validate-only']), /missing evidence path/)

    const missingBead = structuredClone(canonical)
    missingBead.claims.find((claim) => claim.status === 'qualified').ownerBeads = ['haxe.rust-does-not-exist']
    const missingBeadPath = path.join(root, 'missing-bead.json')
    writeJson(missingBeadPath, missingBead)
    expectFailure(run(['--manifest', missingBeadPath, '--validate-only']), /unknown Bead/)

    const unmappedObjection = structuredClone(canonical)
    unmappedObjection.objections[0].claimIds = []
    const unmappedObjectionPath = path.join(root, 'unmapped-objection.json')
    writeJson(unmappedObjectionPath, unmappedObjection)
    expectFailure(run(['--manifest', unmappedObjectionPath, '--validate-only']), /objection.*claimIds/)

    const generatedRoot = path.join(root, 'generated')
    fs.mkdirSync(generatedRoot)
    const generatedPage = path.join(generatedRoot, 'architecture-capability.md')
    const generatedReadme = path.join(generatedRoot, 'README.md')
    const generatedFaq = path.join(generatedRoot, 'faq.md')
    fs.copyFileSync(readmePath, generatedReadme)
    fs.copyFileSync(faqPath, generatedFaq)

    const firstGeneration = run([
      '--write',
      '--page', generatedPage,
      '--readme', generatedReadme,
      '--faq', generatedFaq
    ])
    assert.strictEqual(firstGeneration.status, 0, firstGeneration.stderr || firstGeneration.stdout)
    const first = [generatedPage, generatedReadme, generatedFaq].map((filePath) => fs.readFileSync(filePath, 'utf8'))

    const secondGeneration = run([
      '--write',
      '--page', generatedPage,
      '--readme', generatedReadme,
      '--faq', generatedFaq
    ])
    assert.strictEqual(secondGeneration.status, 0, secondGeneration.stderr || secondGeneration.stdout)
    const second = [generatedPage, generatedReadme, generatedFaq].map((filePath) => fs.readFileSync(filePath, 'utf8'))
    assert.deepStrictEqual(second, first, 'architecture capability generation must be byte-for-byte repeatable')
    assert.match(first[0], /does not authorize stable 1\.0/i)
    assert.match(first[0], /Refuted as a necessity; broad closure open/)
    assert.doesNotMatch(first[0], /\/Users\//)
    assert(!first[0].endsWith('\n\n'), 'generated architecture page must not contain a blank line at EOF')

    fs.writeFileSync(generatedPage, '# stale architecture claims\n')
    expectFailure(
      run(['--check', '--page', generatedPage, '--readme', generatedReadme, '--faq', generatedFaq]),
      /generated architecture capability page is stale/
    )

    fs.writeFileSync(generatedPage, first[0])
    fs.writeFileSync(generatedReadme, replaceGeneratedBlock(first[1], 'stale summary'))
    expectFailure(
      run(['--check', '--page', generatedPage, '--readme', generatedReadme, '--faq', generatedFaq]),
      /README architecture capability summary is stale/
    )
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }

  console.log('[architecture-capability-manifest-test] OK')
}

main()
