#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const policyPath = path.join(repoRoot, 'rust-source-map-policy.json')
const astPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'ast', 'RustAST.hx')
const schemaPath = path.join(repoRoot, 'docs', 'schemas', 'rust-source-map-v1.schema.json')
const beginMarker = '\t// BEGIN GENERATED RUST SOURCE-MAP REASONS'
const endMarker = '\t// END GENERATED RUST SOURCE-MAP REASONS'

function fail(message) {
  console.error(`[rust-source-map-policy] ERROR: ${message}`)
  process.exit(1)
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch (error) {
    fail(`${path.relative(repoRoot, file)} is not valid JSON: ${error.message}`)
  }
}

function validatePolicy(policy) {
  if (policy == null || typeof policy !== 'object' || Array.isArray(policy))
    fail('rust-source-map-policy.json must contain one object')
  if (!Array.isArray(policy.generatedReasons) || policy.generatedReasons.length === 0)
    fail('generatedReasons must contain at least one reason')

  const constructors = new Set()
  const ids = new Set()
  for (const [index, reason] of policy.generatedReasons.entries()) {
    if (reason == null || typeof reason !== 'object' || Array.isArray(reason))
      fail(`generatedReasons[${index}] must be an object`)
    if (typeof reason.constructor !== 'string' || !/^[A-Z][A-Za-z0-9]*$/.test(reason.constructor))
      fail(`generatedReasons[${index}].constructor must be a PascalCase Haxe identifier`)
    if (typeof reason.id !== 'string' || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(reason.id))
      fail(`generatedReasons[${index}].id must be a kebab-case artifact token`)
    if (constructors.has(reason.constructor))
      fail(`duplicate generated-reason constructor: ${reason.constructor}`)
    if (ids.has(reason.id))
      fail(`duplicate generated-reason id: ${reason.id}`)
    constructors.add(reason.constructor)
    ids.add(reason.id)
  }
}

function renderHaxeBlock(reasons) {
  const lines = [beginMarker]
  for (const reason of reasons)
    lines.push(`\tvar ${reason.constructor} = ${JSON.stringify(reason.id)};`)
  lines.push('')
  lines.push('\tpublic inline function id():String {')
  lines.push('\t\treturn this;')
  lines.push('\t}')
  lines.push('')
  lines.push('\t/** Rebuilds a validated reason at serialization boundaries; arbitrary abstract casts fail closed. */')
  lines.push('\tpublic static function fromId(value:String):RustGeneratedOriginReason {')
  lines.push('\t\treturn switch (value) {')
  for (const reason of reasons)
    lines.push(`\t\t\tcase ${JSON.stringify(reason.id)}: ${reason.constructor};`)
  lines.push("\t\t\tcase _: throw 'Unsupported compiler-generated Rust origin reason: $value';")
  lines.push('\t\t};')
  lines.push('\t}')
  lines.push(endMarker)
  return lines.join('\n')
}

function replaceGeneratedBlock(source, replacement) {
  const start = source.indexOf(beginMarker)
  const end = source.indexOf(endMarker)
  if (start < 0 || end < start)
    fail('RustAST.hx is missing the generated source-map reason markers')
  if (source.indexOf(beginMarker, start + beginMarker.length) >= 0 || source.indexOf(endMarker, end + endMarker.length) >= 0)
    fail('RustAST.hx contains duplicate generated source-map reason markers')
  return source.slice(0, start) + replacement + source.slice(end + endMarker.length)
}

function renderSchema(schema, reasons) {
  if (schema == null || typeof schema !== 'object' || schema.$defs == null)
    fail('source-map schema must contain $defs')
  schema.$defs.generatedReason = {enum: reasons.map(reason => reason.id)}
  return `${JSON.stringify(schema, null, 2)}\n`
}

function main() {
  const mode = process.argv[2] || '--check'
  if (mode !== '--check' && mode !== '--write')
    fail('usage: rust-source-map-policy.js [--check|--write]')

  const policy = readJson(policyPath)
  validatePolicy(policy)
  const ast = fs.readFileSync(astPath, 'utf8')
  const expectedAst = replaceGeneratedBlock(ast, renderHaxeBlock(policy.generatedReasons))
  const schema = readJson(schemaPath)
  const expectedSchema = renderSchema(schema, policy.generatedReasons)
  const currentSchema = fs.readFileSync(schemaPath, 'utf8')

  if (mode === '--write') {
    fs.writeFileSync(astPath, expectedAst)
    fs.writeFileSync(schemaPath, expectedSchema)
    console.log('[rust-source-map-policy] synchronized Haxe and JSON-schema generated reasons')
    return
  }

  const stale = []
  if (ast !== expectedAst)
    stale.push('src/reflaxe/rust/ast/RustAST.hx')
  if (currentSchema !== expectedSchema)
    stale.push('docs/schemas/rust-source-map-v1.schema.json')
  if (stale.length > 0)
    fail(`${stale.join(', ')} is stale; run npm run docs:sync:rust-source-map-policy`)
  console.log('[rust-source-map-policy] OK')
}

main()
