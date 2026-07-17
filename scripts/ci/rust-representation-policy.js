#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const policyPath = path.join(repoRoot, 'rust-representation-policy.json')
const haxePath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'analyze', 'RepresentationPlan.hx')
const schemaPath = path.join(repoRoot, 'docs', 'schemas', 'rust-representation-decision-v1.schema.json')
const runtimePlanSchemaPath = path.join(repoRoot, 'docs', 'schemas', 'runtime-plan-v4.schema.json')
const generatedConsumerContractPath = path.join(repoRoot, 'docs', 'generated-consumer-contract.json')
const docsPath = path.join(repoRoot, 'docs', 'rust-representation-plan.md')
const haxeBegin = '// BEGIN GENERATED RUST REPRESENTATION VOCABULARIES'
const haxeEnd = '// END GENERATED RUST REPRESENTATION VOCABULARIES'
const docsBegin = '<!-- BEGIN GENERATED RUST REPRESENTATION VOCABULARY -->'
const docsEnd = '<!-- END GENERATED RUST REPRESENTATION VOCABULARY -->'

function fail(message) {
  throw new Error(`[rust-representation-policy] ${message}`)
}

function loadPolicy() {
  const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'))
  if (policy.schemaVersion !== 1 || policy.decisionSchemaVersion !== 1 || policy.generator !== 'reflaxe.rust') {
    fail('unsupported policy identity or schema version')
  }
  if (!Array.isArray(policy.vocabularies) || policy.vocabularies.length === 0) {
    fail('vocabularies must be a non-empty array')
  }
  const requiredKeys = [
    'sourceValueKinds', 'identityFacts', 'mutationFacts', 'escapeFacts', 'surfaceFacts',
    'nullabilityFacts', 'boundaryKinds', 'representationKinds', 'ownershipPolicies',
    'nullEncodings', 'reusePolicies', 'representationReasons', 'runtimeRequirements', 'requiredBounds'
  ]
  const admittedConsumers = new Set(['representation-decision-v1', 'runtime-plan-v4'])
  const seenKeys = new Set()
  const seenHaxeTypes = new Set()
  for (const vocabulary of policy.vocabularies) {
    if (!vocabulary || !/^[a-z][A-Za-z0-9]*$/.test(vocabulary.key) || !/^[A-Z][A-Za-z0-9]*$/.test(vocabulary.haxeType) ||
        typeof vocabulary.description !== 'string' || vocabulary.description.length === 0 || /[\r\n]|\*\//.test(vocabulary.description) ||
        !Array.isArray(vocabulary.values) || vocabulary.values.length === 0) {
      fail('every vocabulary requires key, haxeType, description, and non-empty values')
    }
    if (seenKeys.has(vocabulary.key)) fail(`duplicate vocabulary key: ${vocabulary.key}`)
    if (seenHaxeTypes.has(vocabulary.haxeType)) fail(`duplicate vocabulary Haxe type: ${vocabulary.haxeType}`)
    seenKeys.add(vocabulary.key)
    seenHaxeTypes.add(vocabulary.haxeType)
    const names = new Set()
    const ids = new Set()
    for (const value of vocabulary.values) {
      if (!value || !/^[A-Z][A-Za-z0-9]*$/.test(value.name) || !/^[a-z][a-z0-9_]*$/.test(value.id) ||
          typeof value.meaning !== 'string' || value.meaning.length === 0 || /[\r\n|]/.test(value.meaning)) {
        fail(`invalid ${vocabulary.key} value: ${JSON.stringify(value)}`)
      }
      if (names.has(value.name) || ids.has(value.id)) fail(`duplicate ${vocabulary.key} name or id: ${value.name}/${value.id}`)
      if (vocabulary.key === 'runtimeRequirements') {
        if (!Array.isArray(value.consumers) || value.consumers.length === 0 ||
            !value.consumers.includes('representation-decision-v1') ||
            value.consumers.some((consumer) => !admittedConsumers.has(consumer)) ||
            new Set(value.consumers).size !== value.consumers.length ||
            value.consumers.join(',') !== ['representation-decision-v1', 'runtime-plan-v4'].filter((consumer) => value.consumers.includes(consumer)).join(',')) {
          fail(`invalid runtimeRequirements consumers for ${value.id}`)
        }
      }
      names.add(value.name)
      ids.add(value.id)
    }
  }
  for (const key of requiredKeys) {
    if (!seenKeys.has(key)) fail(`missing required vocabulary: ${key}`)
  }
  if (seenKeys.size !== requiredKeys.length)
    fail('policy contains an unrecognized vocabulary')
  return policy
}

function vocabulary(policy, key) {
  const found = policy.vocabularies.find((entry) => entry.key === key)
  if (!found) fail(`missing vocabulary: ${key}`)
  return found
}

function renderHaxe(policy) {
  const lines = [haxeBegin]
  for (const entry of policy.vocabularies) {
    lines.push('/**')
    lines.push(`\t${entry.description}`)
    lines.push('')
    lines.push('\tWhy / What / How')
    lines.push('\t- Serialized planner values are closed and generated from `rust-representation-policy.json`.')
    lines.push('\t- Use typed values internally and `fromId` only when rebuilding untrusted report data.')
    lines.push('**/')
    lines.push(`enum abstract ${entry.haxeType}(String) to String {`)
    for (const value of entry.values) lines.push(`\tvar ${value.name} = "${value.id}";`)
    lines.push('')
    lines.push('\tpublic inline function id():String {')
    lines.push('\t\treturn this;')
    lines.push('\t}')
    lines.push('')
    if (entry.key === 'runtimeRequirements') {
      const runtimePlanV4Values = entry.values.filter((value) => value.consumers.includes('runtime-plan-v4'))
      lines.push('\t/**')
      lines.push('\t\tReturns whether runtime-plan schema v4 admits this reason.')
      lines.push('')
      lines.push('\t\tWhy / What / How')
      lines.push('\t\t- Consumer membership belongs to `rust-representation-policy.json`, beside each reason.')
      lines.push('\t\t- Runtime-report code uses this generated helper instead of repeating a second reason list.')
      lines.push('\t**/')
      lines.push('\tpublic inline function isRuntimePlanV4Reason():Bool {')
      lines.push('\t\treturn switch (this) {')
      lines.push(`\t\t\tcase ${runtimePlanV4Values.map((value) => value.name).join(' | ')}: true;`)
      lines.push('\t\t\tcase _: false;')
      lines.push('\t\t};')
      lines.push('\t}')
      lines.push('')
    }
    lines.push(`\tpublic static function fromId(value:String):${entry.haxeType} {`)
    lines.push('\t\treturn switch (value) {')
    for (const value of entry.values) lines.push(`\t\t\tcase "${value.id}": ${value.name};`)
    lines.push(`\t\t\tcase _: throw 'Unsupported ${entry.haxeType} id: $value';`)
    lines.push('\t\t};')
    lines.push('\t}')
    lines.push('}')
    lines.push('')
  }
  lines.push(haxeEnd)
  return lines.join('\n')
}

function ids(policy, key) {
  return vocabulary(policy, key).values.map((value) => value.id)
}

function valuesForConsumer(policy, key, consumer) {
  return vocabulary(policy, key).values.filter((value) => value.consumers.includes(consumer))
}

function renderSchema(policy) {
  const sourcePathPattern = '^(?!/)(?![A-Za-z]:)(?!.*(?:^|/)(?:\\.|\\.\\.)(?:/|$))(?!.*//)[^\\\\\\x00-\\x1f\\x7f]+$'
  const schema = {
    $schema: 'http://json-schema.org/draft-07/schema#',
    $id: 'urn:reflaxe-rust:schema:rust-representation-decision:v1',
    title: 'reflaxe.rust representation decision component schema v1',
    type: 'object',
    additionalProperties: false,
    required: ['schemaVersion', 'generator', 'decisions'],
    properties: {
      schemaVersion: { const: policy.decisionSchemaVersion },
      generator: { const: policy.generator },
      decisions: { type: 'array', uniqueItems: true, items: { $ref: '#/$defs/decision' } }
    },
    $defs: {
      decision: {
        type: 'object',
        additionalProperties: false,
        required: [
          'subjectId', 'sourceKind', 'identity', 'mutation', 'escape', 'surface', 'nullability', 'boundary',
          'representation', 'nullEncoding', 'ownership', 'reuse', 'reason',
          'runtimeRequirements', 'requiredBounds', 'noHxrtEligible', 'origin'
        ],
        allOf: [
          {
            if: { properties: { noHxrtEligible: { const: true } }, required: ['noHxrtEligible'] },
            then: { properties: { runtimeRequirements: { maxItems: 0 } } },
            else: { properties: { runtimeRequirements: { minItems: 1 } } }
          }
        ],
        properties: {
          subjectId: { type: 'string', minLength: 1, pattern: '^[^\\x00-\\x1f\\x7f]+$' },
          sourceKind: { enum: ids(policy, 'sourceValueKinds') },
          identity: { enum: ids(policy, 'identityFacts') },
          mutation: { enum: ids(policy, 'mutationFacts') },
          escape: { enum: ids(policy, 'escapeFacts') },
          surface: { enum: ids(policy, 'surfaceFacts') },
          nullability: { enum: ids(policy, 'nullabilityFacts') },
          boundary: { enum: ids(policy, 'boundaryKinds') },
          representation: { enum: ids(policy, 'representationKinds') },
          nullEncoding: { enum: ids(policy, 'nullEncodings') },
          ownership: { enum: ids(policy, 'ownershipPolicies') },
          reuse: { enum: ids(policy, 'reusePolicies') },
          reason: { enum: ids(policy, 'representationReasons') },
          runtimeRequirements: { type: 'array', uniqueItems: true, items: { enum: ids(policy, 'runtimeRequirements') } },
          requiredBounds: { type: 'array', uniqueItems: true, items: { enum: ids(policy, 'requiredBounds') } },
          noHxrtEligible: { type: 'boolean' },
          origin: { $ref: '#/$defs/origin' }
        }
      },
      origin: {
        type: 'object',
        additionalProperties: false,
        required: ['sourceFile', 'modulePath', 'startByte', 'byteLength'],
        properties: {
          sourceFile: { type: 'string', minLength: 1, pattern: sourcePathPattern },
          modulePath: { type: 'string', pattern: '^[A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*$' },
          startByte: { type: 'integer', minimum: 0 },
          byteLength: { type: 'integer', minimum: 0 }
        }
      }
    }
  }
  return `${JSON.stringify(schema, null, 2)}\n`
}

function renderDocs(policy) {
  const lines = [docsBegin, '', '| Vocabulary | ID | Meaning |', '| --- | --- | --- |']
  for (const entry of policy.vocabularies) {
    for (const value of entry.values) {
      lines.push(`| \`${entry.key}\` | \`${value.id}\` | ${value.meaning} |`)
    }
  }
  lines.push('', docsEnd)
  return lines.join('\n')
}

function renderRuntimeReasonSchema(policy) {
  const values = valuesForConsumer(policy, 'runtimeRequirements', 'runtime-plan-v4').map((value) => value.id)
  const lines = ['    "reasonKind": {', '      "enum": [']
  for (let index = 0; index < values.length; index++) {
    const comma = index === values.length - 1 ? '' : ','
    lines.push(`        ${JSON.stringify(values[index])}${comma}`)
  }
  lines.push('      ]', '    }')
  return lines.join('\n')
}

function replaceRuntimeReasonSchema(content, replacement) {
  const startMarker = '    "reasonKind": {'
  const nextMarker = '    "familyStdPin": {'
  const start = content.indexOf(startMarker)
  const next = content.indexOf(nextMarker, start)
  if (start < 0 || next < 0)
    fail('runtime-plan-v4.schema.json is missing the reasonKind/familyStdPin boundary')
  return content.slice(0, start) + replacement + ',\n' + content.slice(next)
}

function renderGeneratedConsumerContract(policy) {
  const content = fs.readFileSync(generatedConsumerContractPath, 'utf8')
  const reportStart = content.indexOf('      "id": "runtime-plan-v4"')
  const groupStart = content.indexOf('          "path": "$.runtimeRequirements[*].reasonKind"', reportStart)
  const valuesStart = content.indexOf('          "values": [', groupStart)
  const valuesEnd = content.indexOf('\n          ]', valuesStart)
  if (reportStart < 0 || groupStart < 0 || valuesStart < 0 || valuesEnd < 0)
    fail('generated-consumer-contract.json is missing the runtime-plan-v4 reason value block')

  const values = valuesForConsumer(policy, 'runtimeRequirements', 'runtime-plan-v4')
  const lines = ['          "values": [']
  for (let index = 0; index < values.length; index++) {
    const value = values[index]
    const comma = index === values.length - 1 ? '' : ','
    lines.push(`            { "id": ${JSON.stringify(value.id)}, "meaning": ${JSON.stringify(value.meaning)} }${comma}`)
  }
  lines.push('          ]')
  return content.slice(0, valuesStart) + lines.join('\n') + content.slice(valuesEnd + '\n          ]'.length)
}

function replaceBlock(content, begin, end, replacement, label) {
  const start = content.indexOf(begin)
  const finish = content.indexOf(end)
  if (start < 0 || finish < 0 || finish < start) fail(`${label} is missing generated markers`)
  return content.slice(0, start) + replacement + content.slice(finish + end.length)
}

function expectedFiles(policy) {
  const haxe = replaceBlock(fs.readFileSync(haxePath, 'utf8'), haxeBegin, haxeEnd, renderHaxe(policy), 'RepresentationPlan.hx')
  const docs = replaceBlock(fs.readFileSync(docsPath, 'utf8'), docsBegin, docsEnd, renderDocs(policy), 'representation docs')
  const runtimePlanSchema = replaceRuntimeReasonSchema(
    fs.readFileSync(runtimePlanSchemaPath, 'utf8'),
    renderRuntimeReasonSchema(policy)
  )
  return new Map([
    [haxePath, haxe],
    [schemaPath, renderSchema(policy)],
    [runtimePlanSchemaPath, runtimePlanSchema],
    [generatedConsumerContractPath, renderGeneratedConsumerContract(policy)],
    [docsPath, docs]
  ])
}

function main() {
  const mode = process.argv[2] || '--check'
  if (mode !== '--check' && mode !== '--write') fail(`unknown mode: ${mode}`)
  const files = expectedFiles(loadPolicy())
  let drift = false
  for (const [file, expected] of files) {
    const actual = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : ''
    if (actual === expected) continue
    if (mode === '--write') {
      fs.mkdirSync(path.dirname(file), { recursive: true })
      fs.writeFileSync(file, expected)
    } else {
      drift = true
      process.stderr.write(`[rust-representation-policy] drift: ${path.relative(repoRoot, file)}\n`)
    }
  }
  if (drift) process.exit(1)
  process.stdout.write(`[rust-representation-policy] ${mode === '--write' ? 'generated' : 'OK'}\n`)
}

main()
