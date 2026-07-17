#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const path = require('path')
const Ajv = require('ajv')

const repoRoot = path.resolve(__dirname, '..', '..')
const haxeShim = path.join(repoRoot, 'node_modules', 'lix', 'bin', 'haxeshim.js')
const harnessPath = path.join(repoRoot, 'scripts', 'ci', 'harness.sh')
const policyPath = path.join(repoRoot, 'rust-representation-policy.json')
const schemaPath = path.join(repoRoot, 'docs', 'schemas', 'rust-representation-decision-v1.schema.json')
const generatorPath = path.join(repoRoot, 'scripts', 'ci', 'rust-representation-policy.js')

function run(command, args) {
  return cp.spawnSync(command, args, { cwd: repoRoot, encoding: 'utf8' })
}

function output(result) {
  return `${result.stdout || ''}\n${result.stderr || ''}`
}

function main() {
  assert(fs.existsSync(haxeShim), 'project-pinned Haxe shim must exist')
  assert(fs.existsSync(policyPath), 'the representation vocabulary must have one structured policy source')
  assert(fs.existsSync(schemaPath), 'the representation decision schema must be generated from policy')
  assert(fs.existsSync(generatorPath), 'the representation policy generator must exist')
  assert.match(
    fs.readFileSync(harnessPath, 'utf8'),
    /typed Rust representation-plan contract" npm run test:rust-representation-plan/,
    'the compiler snapshot stage must run the representation-plan contract'
  )

  const generator = run(process.execPath, [generatorPath, '--check'])
  assert.strictEqual(generator.status, 0, output(generator))

  const args = [
    path.join('node_modules', 'lix', 'bin', 'haxeshim.js'),
    '-cp', 'src',
    '-cp', 'test/compiler',
    '-main', 'RustRepresentationPlanContract',
    '--interp'
  ]
  const first = run(process.execPath, args)
  assert.strictEqual(first.status, 0, output(first))
  const second = run(process.execPath, args)
  assert.strictEqual(second.status, 0, output(second))
  assert.strictEqual(first.stdout, second.stdout, 'representation-plan serialization must be byte-for-byte repeatable')
  assert.strictEqual(first.stderr, second.stderr, 'representation-plan diagnostics must be repeatable')

  const lines = first.stdout.trimEnd().split('\n')
  assert.deepStrictEqual(lines.slice(0, 5), [
    'shared_identity|shared|clone_when_needed|object_identity,reference_mutation',
    'owned_value|move|move_once',
    'clone,send,sync,static',
    'send,static',
    'haxe_string_semantics,nullable_compat'
  ])

  const snapshot = JSON.parse(lines.slice(5).join('\n'))
  const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'))
  const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'))
  const runtimeVocabulary = policy.vocabularies.find((entry) => entry.key === 'runtimeRequirements').values
  const decisionReasonIds = schema.$defs.decision.properties.runtimeRequirements.items.enum
  assert.deepStrictEqual(decisionReasonIds, runtimeVocabulary.map((value) => value.id),
    'decision schema runtime reasons must come from the complete policy vocabulary')

  const runtimePlanSchema = JSON.parse(fs.readFileSync(path.join(repoRoot, 'docs', 'schemas', 'runtime-plan-v4.schema.json'), 'utf8'))
  const v4ReasonIds = runtimeVocabulary.filter((value) => value.consumers.includes('runtime-plan-v4')).map((value) => value.id)
  assert.deepStrictEqual(runtimePlanSchema.$defs.reasonKind.enum, v4ReasonIds,
    'immutable runtime-plan v4 reasons must come from their policy consumer scope')

  const generatedConsumer = JSON.parse(fs.readFileSync(path.join(repoRoot, 'docs', 'generated-consumer-contract.json'), 'utf8'))
  const v4Report = generatedConsumer.reports.find((report) => report.id === 'runtime-plan-v4')
  const v4StableReasons = v4Report.stableIdentifiers.find((group) => group.path === '$.runtimeRequirements[*].reasonKind').values
  assert.deepStrictEqual(v4StableReasons, runtimeVocabulary.filter((value) => value.consumers.includes('runtime-plan-v4')).map((value) => ({
    id: value.id,
    meaning: value.meaning
  })), 'runtime-plan v4 stable identifiers must come from the same scoped policy values')

  const ajv = new Ajv({ allErrors: true, strict: false })
  const validate = ajv.compile(schema)
  assert(validate(snapshot), JSON.stringify(validate.errors, null, 2))

  const inventedReason = structuredClone(snapshot)
  inventedReason.decisions[0].reason = 'invented-reason'
  assert.strictEqual(validate(inventedReason), false, 'schema must reject reasons outside the closed policy vocabulary')

  const unsafePath = structuredClone(snapshot)
  unsafePath.decisions[0].origin.sourceFile = '../private/Main.hx'
  assert.strictEqual(validate(unsafePath), false, 'schema must reject traversal in source origins')

  const drivePath = structuredClone(snapshot)
  drivePath.decisions[0].origin.sourceFile = 'C:private/Main.hx'
  assert.strictEqual(validate(drivePath), false, 'schema must reject drive-relative source origins')

  const invalidModulePath = structuredClone(snapshot)
  invalidModulePath.decisions[0].origin.modulePath = 'Main..Node'
  assert.strictEqual(validate(invalidModulePath), false, 'schema must reject invalid Haxe module-path segments')

  const invalidLength = structuredClone(snapshot)
  invalidLength.decisions[0].origin.byteLength = -1
  assert.strictEqual(validate(invalidLength), false, 'schema must reject negative source byte lengths')

  const dishonestEligibility = structuredClone(snapshot)
  dishonestEligibility.decisions[0].noHxrtEligible = true
  assert.strictEqual(validate(dishonestEligibility), false, 'schema must keep no-hxrt eligibility consistent with runtime reasons')

  const dishonestIneligibility = structuredClone(snapshot)
  dishonestIneligibility.decisions.find((decision) => decision.runtimeRequirements.length === 0).noHxrtEligible = false
  assert.strictEqual(validate(dishonestIneligibility), false, 'schema must not invent a runtime dependency without a reason')

  const inventedNullEncoding = structuredClone(snapshot)
  inventedNullEncoding.decisions[0].nullEncoding = 'nullable_value'
  assert.strictEqual(validate(inventedNullEncoding), false, 'schema must reject null encodings outside the closed policy vocabulary')

  const controlSubject = structuredClone(snapshot)
  controlSubject.decisions[0].subjectId = 'Main.Bad\tSubject'
  assert.strictEqual(validate(controlSubject), false, 'schema must reject control characters in decision subjects')

  const duplicate = structuredClone(snapshot)
  duplicate.decisions.push(structuredClone(duplicate.decisions[0]))
  assert.strictEqual(validate(duplicate), false, 'schema must reject exact duplicate decisions')

  console.log('[rust-representation-plan-test] OK')
}

main()
