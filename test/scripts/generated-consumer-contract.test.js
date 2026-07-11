#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const checker = path.join(repoRoot, 'scripts', 'ci', 'generated-consumer-contract-check.js')
const { schemaDigest } = require(checker)
const manifestPath = path.join(repoRoot, 'docs', 'generated-consumer-contract.json')
const baselinePath = path.join(repoRoot, 'test', 'compatibility-baselines', 'generated-consumer-contract-initial.json')

function run(args = []) {
  return cp.spawnSync(process.execPath, [checker, ...args], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`)
}

function expectFailure(result, pattern) {
  assert.notStrictEqual(result.status, 0, 'generated-consumer guard unexpectedly succeeded')
  assert.match(`${result.stdout}\n${result.stderr}`, pattern)
}

function main() {
  assert(fs.existsSync(checker), 'generated-consumer contract guard must exist')
  assert(fs.existsSync(manifestPath), 'generated-consumer contract manifest must exist')
  assert(fs.existsSync(baselinePath), 'generated-consumer compatibility baseline must exist')

  const baseline = run()
  assert.strictEqual(baseline.status, 0, baseline.stderr || baseline.stdout)

  const canonical = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  assert.deepStrictEqual(
    canonical.reports.map((report) => [report.filename, report.schemaVersion]),
    [
      ['metal_report.json', 1],
      ['contract_report.json', 6],
      ['runtime_plan.json', 4],
      ['optimizer_plan.json', 2]
    ]
  )
  assert.strictEqual(canonical.unknownFieldPolicy, 'consumers-must-ignore')
  assert.strictEqual(canonical.markdownPolicy, 'human-only-not-machine-contract')

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-generated-contract-'))
  fs.mkdirSync(path.join(repoRoot, '.cache'), { recursive: true })
  const schemaRoot = fs.mkdtempSync(path.join(repoRoot, '.cache', 'generated-contract-schema-'))
  try {
    const removedField = structuredClone(canonical)
    removedField.reports[0].protectedFields = removedField.reports[0].protectedFields.filter(
      (field) => field.path !== '$.overallScore'
    )
    const removedFieldPath = path.join(root, 'removed-field.json')
    writeJson(removedFieldPath, removedField)
    expectFailure(run(['--manifest', removedFieldPath, '--skip-public']), /(removed protected field|schema-required field).*overallScore/)

    const changedType = structuredClone(canonical)
    changedType.reports[1].protectedFields.find((field) => field.path === '$.schemaVersion').type = 'string'
    const changedTypePath = path.join(root, 'changed-type.json')
    writeJson(changedTypePath, changedType)
    expectFailure(run(['--manifest', changedTypePath, '--skip-public']), /(changed protected field type.*schemaVersion|schemaVersion.*disagrees with schema type)/)

    const repurposedIdentifier = structuredClone(canonical)
    repurposedIdentifier.reports[2].stableIdentifiers[0].values[0].meaning = 'repurposed meaning'
    const repurposedIdentifierPath = path.join(root, 'repurposed-identifier.json')
    writeJson(repurposedIdentifierPath, repurposedIdentifier)
    expectFailure(run(['--manifest', repurposedIdentifierPath, '--skip-public']), /changed stable identifier meaning/)

    const removedArtifactPromise = structuredClone(canonical)
    removedArtifactPromise.generatedArtifacts[0].protectedContract.shift()
    const removedArtifactPromisePath = path.join(root, 'removed-artifact-promise.json')
    writeJson(removedArtifactPromisePath, removedArtifactPromise)
    expectFailure(run(['--manifest', removedArtifactPromisePath, '--skip-public']), /removed generated-artifact promise/)

    const redirectedBaseline = structuredClone(canonical)
    redirectedBaseline.compatibilityBaseline = 'test/compatibility-baselines/replacement.json'
    const redirectedBaselinePath = path.join(root, 'redirected-baseline.json')
    writeJson(redirectedBaselinePath, redirectedBaseline)
    expectFailure(run(['--manifest', redirectedBaselinePath, '--skip-public']), /compatibilityBaseline must remain/)

    const remappedDefine = structuredClone(canonical)
    remappedDefine.reports[0].emissionDefine = 'rust_contract_report'
    const remappedDefinePath = path.join(root, 'remapped-define.json')
    writeJson(remappedDefinePath, remappedDefine)
    expectFailure(run(['--manifest', remappedDefinePath, '--skip-public']), /changed report emission control/)

    const editedSchemaManifest = structuredClone(canonical)
    const canonicalSchemaPath = path.join(repoRoot, editedSchemaManifest.reports[3].schema)
    const editedSchema = JSON.parse(fs.readFileSync(canonicalSchemaPath, 'utf8'))
    const originalSchema = structuredClone(editedSchema)
    assert.strictEqual(schemaDigest(originalSchema), schemaDigest(JSON.parse(JSON.stringify(originalSchema))), 'schema digest must ignore JSON formatting')
    delete editedSchema.$defs.metric.properties.id
    editedSchema.$defs.metric.required = editedSchema.$defs.metric.required.filter((field) => field !== 'id')
    assert.notStrictEqual(schemaDigest(originalSchema), schemaDigest(editedSchema), 'schema digest must detect semantic shape changes')
    const editedSchemaPath = path.join(schemaRoot, 'optimizer-plan-v2.schema.json')
    writeJson(editedSchemaPath, editedSchema)
    editedSchemaManifest.reports[3].schema = path.relative(repoRoot, editedSchemaPath).split(path.sep).join('/')
    const editedSchemaManifestPath = path.join(root, 'edited-schema.json')
    writeJson(editedSchemaManifestPath, editedSchemaManifest)
    expectFailure(run(['--manifest', editedSchemaManifestPath, '--skip-public']), /(changed protected schema path|changed immutable versioned schema)/)

    const first = run(['--print-signature'])
    const second = run(['--print-signature'])
    assert.strictEqual(first.status, 0, first.stderr)
    assert.strictEqual(second.status, 0, second.stderr)
    assert.strictEqual(first.stdout, second.stdout, 'compatibility signature must be byte-for-byte repeatable')
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
    fs.rmSync(schemaRoot, { recursive: true, force: true })
  }

  console.log('[generated-consumer-contract-test] OK')
}

main()
