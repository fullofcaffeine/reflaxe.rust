#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

const scriptRepoRoot = path.resolve(__dirname, '..', '..')
const enumBegin = '\t// BEGIN GENERATED RUST RAW AUTHORITIES'
const enumEnd = '\t// END GENERATED RUST RAW AUTHORITIES'
const factoriesBegin = '\t// BEGIN GENERATED RUST RAW FACTORIES'
const factoriesEnd = '\t// END GENERATED RUST RAW FACTORIES'

function fail(message) {
  console.error(`[rust-raw-authority-policy] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  let mode = '--check'
  let root = scriptRepoRoot
  for (let i = 0; i < argv.length; i++) {
    const value = argv[i]
    if (value === '--check' || value === '--write') {
      mode = value
    } else if (value === '--root') {
      if (i + 1 >= argv.length) fail('--root requires a path')
      root = path.resolve(argv[++i])
    } else {
      fail(`unknown argument: ${value}`)
    }
  }
  return {mode, root}
}

function readJson(file, label) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'))
  } catch (error) {
    fail(`${label} is not valid JSON: ${error.message}`)
  }
}

function requireText(value, label, pattern) {
  if (typeof value !== 'string' || value.length === 0 || (pattern != null && !pattern.test(value)))
    fail(`${label} has an invalid value`)
}

function validatePolicy(policy) {
  if (policy == null || typeof policy !== 'object' || Array.isArray(policy))
    fail('rust-raw-authority-policy.json must contain one object')
  if (policy.schemaVersion !== 1)
    fail('schemaVersion must be 1')
  if (!Array.isArray(policy.scanRoots) || policy.scanRoots.length === 0)
    fail('scanRoots must be a non-empty array')
  if (!Array.isArray(policy.boundaries) || policy.boundaries.length === 0)
    fail('boundaries must be a non-empty array')
  if (!Array.isArray(policy.structuralRequirements) || policy.structuralRequirements.length === 0)
    fail('structuralRequirements must be a non-empty array')

  const constructors = new Set()
  const factories = new Set()
  const authorityReasons = new Set()
  for (const [index, boundary] of policy.boundaries.entries()) {
    const prefix = `boundaries[${index}]`
    if (boundary == null || typeof boundary !== 'object' || Array.isArray(boundary))
      fail(`${prefix} must be an object`)
    requireText(boundary.constructor, `${prefix}.constructor`, /^Raw[A-Z][A-Za-z0-9]*$/)
    requireText(boundary.factory, `${prefix}.factory`, /^[a-z][A-Za-z0-9]*At$/)
    requireText(boundary.authorityId, `${prefix}.authorityId`, /^(metadata|source)-owned$/)
    requireText(boundary.reasonId, `${prefix}.reasonId`, /^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    requireText(boundary.owner, `${prefix}.owner`)
    requireText(boundary.structuralEnvelope, `${prefix}.structuralEnvelope`)
    if (boundary.authorityId === 'compiler-owned')
      fail(`${prefix} attempts to restore compiler-owned raw authority`)
    if (constructors.has(boundary.constructor)) fail(`duplicate raw constructor: ${boundary.constructor}`)
    if (factories.has(boundary.factory)) fail(`duplicate raw factory: ${boundary.factory}`)
    const authorityReason = `${boundary.authorityId}:${boundary.reasonId}`
    if (authorityReasons.has(authorityReason)) fail(`duplicate raw authority/reason: ${authorityReason}`)
    constructors.add(boundary.constructor)
    factories.add(boundary.factory)
    authorityReasons.add(authorityReason)
  }

  const requirementIds = new Set()
  for (const [index, requirement] of policy.structuralRequirements.entries()) {
    const prefix = `structuralRequirements[${index}]`
    if (requirement == null || typeof requirement !== 'object' || Array.isArray(requirement))
      fail(`${prefix} must be an object`)
    requireText(requirement.id, `${prefix}.id`, /^[a-z0-9]+(?:-[a-z0-9]+)*$/)
    requireText(requirement.source, `${prefix}.source`)
    if (!Array.isArray(requirement.requiredTokens) || requirement.requiredTokens.length === 0)
      fail(`${prefix}.requiredTokens must be a non-empty array`)
    for (const [tokenIndex, token] of requirement.requiredTokens.entries())
      requireText(token, `${prefix}.requiredTokens[${tokenIndex}]`)
    if (requirementIds.has(requirement.id)) fail(`duplicate structural requirement: ${requirement.id}`)
    requirementIds.add(requirement.id)
  }
}

function replaceGeneratedBlock(source, begin, end, replacement, label) {
  const start = source.indexOf(begin)
  const finish = source.indexOf(end)
  if (start < 0 || finish < start)
    fail(`${label} is missing generated markers`)
  if (source.indexOf(begin, start + begin.length) >= 0 || source.indexOf(end, finish + end.length) >= 0)
    fail(`${label} contains duplicate generated markers`)
  return source.slice(0, start) + replacement + source.slice(finish + end.length)
}

function renderEnum(boundaries) {
  return [
    enumBegin,
    ...boundaries.map(boundary => `\t${boundary.constructor};`),
    enumEnd
  ].join('\n')
}

function renderFactories(boundaries) {
  const lines = [factoriesBegin]
  for (const boundary of boundaries) {
    lines.push(`\tpublic static function ${boundary.factory}(code:String, pos:Position):RustRawCode {`)
    lines.push(`\t\treturn new RustRawCode(code, ${boundary.constructor}, OriginHaxeSource(pos));`)
    lines.push('\t}')
    lines.push('')
  }
  lines.push('\tpublic function authorityId():String {')
  lines.push('\t\treturn switch (authority) {')
  for (const boundary of boundaries)
    lines.push(`\t\t\tcase ${boundary.constructor}: ${JSON.stringify(boundary.authorityId)};`)
  lines.push('\t\t};')
  lines.push('\t}')
  lines.push('')
  lines.push('\tpublic function reasonId():String {')
  lines.push('\t\treturn switch (authority) {')
  for (const boundary of boundaries)
    lines.push(`\t\t\tcase ${boundary.constructor}: ${JSON.stringify(boundary.reasonId)};`)
  lines.push('\t\t};')
  lines.push('\t}')
  lines.push('')
  lines.push('\tstatic function requireAuthority(value:RustRawAuthority):RustRawAuthority {')
  lines.push('\t\tif (value == null)')
  lines.push('\t\t\tthrow "Classified raw Rust requires an authority";')
  lines.push('\t\tswitch (value) {')
  for (const boundary of boundaries)
    lines.push(`\t\t\tcase ${boundary.constructor}:`)
  lines.push('\t\t}')
  lines.push('\t\treturn value;')
  lines.push('\t}')
  lines.push(factoriesEnd)
  return lines.join('\n')
}

function maskNonCode(source) {
  const chars = source.split('')
  let state = 'code'
  let quote = null
  let escaped = false
  for (let i = 0; i < chars.length; i++) {
    const current = source[i]
    const next = i + 1 < chars.length ? source[i + 1] : ''
    if (state === 'code') {
      if (current === '/' && next === '/') {
        chars[i] = chars[i + 1] = ' '
        i++
        state = 'line-comment'
      } else if (current === '/' && next === '*') {
        chars[i] = chars[i + 1] = ' '
        i++
        state = 'block-comment'
      } else if (current === '"' || current === "'") {
        chars[i] = ' '
        quote = current
        escaped = false
        state = 'string'
      }
    } else if (state === 'line-comment') {
      if (current === '\n') state = 'code'
      else chars[i] = ' '
    } else if (state === 'block-comment') {
      if (current === '*' && next === '/') {
        chars[i] = chars[i + 1] = ' '
        i++
        state = 'code'
      } else if (current !== '\n') {
        chars[i] = ' '
      }
    } else if (state === 'string') {
      if (current !== '\n') chars[i] = ' '
      if (escaped) {
        escaped = false
      } else if (current === '\\') {
        escaped = true
      } else if (current === quote) {
        state = 'code'
        quote = null
      }
    }
  }
  return chars.join('')
}

function walkHaxeFiles(directory, output) {
  if (!fs.existsSync(directory)) return
  for (const entry of fs.readdirSync(directory, {withFileTypes: true}).sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(directory, entry.name)
    if (entry.isDirectory()) walkHaxeFiles(full, output)
    else if (entry.isFile() && entry.name.endsWith('.hx')) output.push(full)
  }
}

function lineAt(source, index) {
  let line = 1
  for (let i = 0; i < index; i++) if (source.charCodeAt(i) === 10) line++
  return line
}

function enclosingFunction(masked, index) {
  const prefix = masked.slice(0, index)
  const pattern = /\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/g
  let match
  let result = '<module>'
  while ((match = pattern.exec(prefix)) != null) result = match[1]
  return result
}

function collectCallSites(root, policy, astPath) {
  const allowed = new Map(policy.boundaries.map(boundary => [boundary.factory, boundary]))
  const files = []
  for (const scanRoot of policy.scanRoots) walkHaxeFiles(path.join(root, scanRoot), files)
  files.sort((a, b) => a.localeCompare(b))
  const callSites = []
  for (const file of files) {
    const source = fs.readFileSync(file, 'utf8')
    const masked = maskNonCode(source)
    const relative = path.relative(root, file).split(path.sep).join('/')
    const factoryPattern = /\bRustRawCode\.([A-Za-z_][A-Za-z0-9_]*)\s*\(/g
    let match
    while ((match = factoryPattern.exec(masked)) != null) {
      const factory = match[1]
      const boundary = allowed.get(factory)
      if (boundary == null)
        fail(`unsupported raw factory RustRawCode.${factory} at ${relative}:${lineAt(source, match.index)}; compiler-owned raw authority is closed`)
      callSites.push({
        path: relative,
        line: lineAt(source, match.index),
        enclosingFunction: enclosingFunction(masked, match.index),
        factory,
        authorityId: boundary.authorityId,
        reasonId: boundary.reasonId
      })
    }

    if (path.resolve(file) !== path.resolve(astPath)) {
      const constructor = /\bnew\s+RustRawCode\s*\(/g.exec(masked)
      if (constructor != null)
        fail(`direct RustRawCode construction at ${relative}:${lineAt(source, constructor.index)} bypasses the closed factories`)
    }
  }
  return callSites.sort((a, b) => a.path.localeCompare(b.path) || a.line - b.line || a.factory.localeCompare(b.factory))
}

function validateStructuralRequirements(root, requirements, generatedAst, astRelative) {
  for (const requirement of requirements) {
    const source = requirement.source === astRelative
      ? generatedAst
      : fs.readFileSync(path.join(root, requirement.source), 'utf8')
    for (const token of requirement.requiredTokens) {
      if (!source.includes(token))
        fail(`structural requirement ${requirement.id} is missing ${JSON.stringify(token)} from ${requirement.source}`)
    }
  }
}

function renderInventory(policy, callSites) {
  const counts = {metadataOwned: 0, sourceOwned: 0}
  for (const site of callSites) {
    if (site.authorityId === 'metadata-owned') counts.metadataOwned++
    if (site.authorityId === 'source-owned') counts.sourceOwned++
  }
  return `${JSON.stringify({
    schemaVersion: 1,
    sourceOfTruth: 'rust-raw-authority-policy.json',
    summary: {
      compilerOwnedRawCallSites: 0,
      metadataOwnedRawCallSites: counts.metadataOwned,
      sourceOwnedRawCallSites: counts.sourceOwned,
      totalRawCallSites: callSites.length,
      structuralRequirementCount: policy.structuralRequirements.length
    },
    boundaries: policy.boundaries,
    structuralRequirements: policy.structuralRequirements.map(requirement => ({
      id: requirement.id,
      source: requirement.source
    })),
    callSites
  }, null, 2)}\n`
}

function main() {
  const {mode, root} = parseArgs(process.argv.slice(2))
  const policyPath = path.join(root, 'rust-raw-authority-policy.json')
  const astRelative = 'src/reflaxe/rust/ast/RustAST.hx'
  const astPath = path.join(root, astRelative)
  const inventoryPath = path.join(root, 'docs', 'rust-raw-authority-inventory.json')
  const policy = readJson(policyPath, path.relative(root, policyPath))
  validatePolicy(policy)

  const ast = fs.readFileSync(astPath, 'utf8')
  const withEnum = replaceGeneratedBlock(ast, enumBegin, enumEnd, renderEnum(policy.boundaries), astRelative)
  const generatedAst = replaceGeneratedBlock(withEnum, factoriesBegin, factoriesEnd, renderFactories(policy.boundaries), astRelative)
  validateStructuralRequirements(root, policy.structuralRequirements, generatedAst, astRelative)
  const callSites = collectCallSites(root, policy, astPath)
  const inventory = renderInventory(policy, callSites)

  if (mode === '--write') {
    fs.writeFileSync(astPath, generatedAst)
    fs.mkdirSync(path.dirname(inventoryPath), {recursive: true})
    fs.writeFileSync(inventoryPath, inventory)
    console.log(`[rust-raw-authority-policy] synchronized typed factories and ${callSites.length} reviewed raw call site(s)`)
    return
  }

  const stale = []
  if (ast !== generatedAst) stale.push(astRelative)
  if (!fs.existsSync(inventoryPath) || fs.readFileSync(inventoryPath, 'utf8') !== inventory)
    stale.push('docs/rust-raw-authority-inventory.json')
  if (stale.length > 0)
    fail(`${stale.join(', ')} is stale; run npm run docs:sync:rust-raw-authority and review every raw call site`)
  console.log(`[rust-raw-authority-policy] OK: 0 compiler-owned and ${callSites.length} external/source raw call site(s)`)
}

main()
