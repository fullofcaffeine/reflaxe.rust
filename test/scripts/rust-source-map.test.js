#!/usr/bin/env node

const assert = require('assert')
const Ajv = require('ajv')
const crypto = require('crypto')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const haxeShim = path.join(repoRoot, 'node_modules', 'lix', 'bin', 'haxeshim.js')
const fixture = path.join(repoRoot, 'test', 'positive', 'rust_source_map')
const harnessPath = path.join(repoRoot, 'scripts', 'ci', 'harness.sh')
const astPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'ast', 'RustAST.hx')
const printerPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'ast', 'RustASTPrinter.hx')
const sourceMapPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustSourceMap.hx')
const sourceMapSchemaPath = path.join(repoRoot, 'docs', 'schemas', 'rust-source-map-v1.schema.json')
const passDir = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'passes')

function runHaxe(args, cwd = repoRoot) {
  return cp.spawnSync(process.execPath, [haxeShim, ...args], { cwd, encoding: 'utf8' })
}

function output(result) {
  return `${result.stdout || ''}\n${result.stderr || ''}`
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex')
}

function assertPrivatePath(value, label, forbiddenRoots) {
  assert(!path.isAbsolute(value), `${label} must be relative: ${value}`)
  assert(!value.split(/[\\/]+/).includes('..'), `${label} must not escape its stable root: ${value}`)
  for (const root of forbiddenRoots) {
    assert(!value.includes(root), `${label} leaked a machine-local root: ${value}`)
  }
}

function main() {
  const validateArtifact = new Ajv({allErrors: true, strict: true}).compile(
    JSON.parse(fs.readFileSync(sourceMapSchemaPath, 'utf8'))
  )
  assert.match(
    fs.readFileSync(harnessPath, 'utf8'),
    /deterministic Rust source-map contract" npm run test:rust-source-map/,
    'the full harness must run the deterministic source-map contract'
  )

  const macroArgs = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '--macro', 'RustSourceMapContract.run()',
    '--no-output'
  ]
  const first = runHaxe(macroArgs)
  assert.strictEqual(first.status, 0, output(first))
  const second = runHaxe(macroArgs)
  assert.strictEqual(second.status, 0, output(second))
  assert.strictEqual(first.stdout, second.stdout, 'source-map artifact bytes must be repeatable')
  assert.strictEqual(first.stderr, second.stderr, 'source-map diagnostics must be repeatable')
  const macroMap = JSON.parse(first.stdout)
  assert.strictEqual(macroMap.schemaVersion, 1)
  assert(validateArtifact(macroMap), `macro source map violates its schema: ${JSON.stringify(validateArtifact.errors)}`)

  const noHxrtArgs = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '--macro', 'RustSourceMapContract.rejectWrappedHxrt()',
    '--no-output'
  ]
  const firstNoHxrt = runHaxe(noHxrtArgs)
  const secondNoHxrt = runHaxe(noHxrtArgs)
  assert.notStrictEqual(firstNoHxrt.status, 0,
    'rust_no_hxrt must reject a runtime path below item, statement, and expression origins')
  assert.strictEqual(firstNoHxrt.stdout, secondNoHxrt.stdout,
    'origin-wrapped no-hxrt output must be repeatable')
  assert.strictEqual(firstNoHxrt.stderr, secondNoHxrt.stderr,
    'origin-wrapped no-hxrt diagnostics must be repeatable')
  assert.match(output(firstNoHxrt), /HXRS-NO-HXRT-EMITTED-RUNTIME/,
    'origin-wrapped path rejection must come from emitted-runtime policy')

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-source-map-'))
  try {
    const encoded = []
    for (const runName of ['first', 'second']) {
      const outDir = path.join(root, runName)
      const compiled = runHaxe(['compile.hxml', '-D', `rust_output=${outDir}`, '-D', 'rust_no_build'], fixture)
      assert.strictEqual(compiled.status, 0, output(compiled))
      const artifactPath = path.join(outDir, 'rust-source-map.json')
      assert(fs.existsSync(artifactPath), 'compiler did not emit rust-source-map.json')
      encoded.push(fs.readFileSync(artifactPath, 'utf8'))
    }
    assert.strictEqual(encoded[0], encoded[1], 'two clean compiler runs emitted different source-map bytes')

    const artifact = JSON.parse(encoded[0])
    assert.strictEqual(artifact.schemaVersion, 1)
    assert.strictEqual(artifact.generator, 'reflaxe.rust')
    assert(validateArtifact(artifact), `compiler source map violates its schema: ${JSON.stringify(validateArtifact.errors)}`)
    const mappedFile = artifact.files.find(file => file.generatedFile === 'src/main.rs')
    assert(mappedFile, 'source map must name the exact generated main file')
    const rustSource = fs.readFileSync(path.join(root, 'first', 'src', 'main.rs'), 'utf8')
    const sourceText = fs.readFileSync(path.join(fixture, 'Main.hx'), 'utf8')
    assert.strictEqual(mappedFile.byteLength, Buffer.byteLength(rustSource))
    assert.strictEqual(mappedFile.contentHash, sha256(rustSource))
    assert.match(
      rustSource,
      /__hx_match_value @ Option::Some\(_\) => __hx_match_value/,
      'an origin-wrapped whole-scrutinee arm must keep the clone-free Rust alias pattern'
    )
    assert.doesNotMatch(
      rustSource,
      /match value\.clone\(\)/,
      'source provenance must not make a generic Option switch require T: Clone'
    )
    const aliasNeedle = '=> __hx_match_value'
    const aliasGeneratedStart = Buffer.from(
      rustSource.slice(0, rustSource.indexOf(aliasNeedle) + '=> '.length)
    ).length
    const aliasSourceNeedle = 'case Some(_): value;'
    const aliasSourceStart = Buffer.from(
      sourceText.slice(0, sourceText.indexOf(aliasSourceNeedle) + 'case Some(_): '.length)
    ).length
    assert(mappedFile.mappings.some(mapping =>
      mapping.origin.kind === 'haxe-source' &&
      mapping.generated.startByte <= aliasGeneratedStart &&
      mapping.generated.endByte > aliasGeneratedStart &&
      mapping.origin.source.startByte <= aliasSourceStart &&
      mapping.origin.source.endByte > aliasSourceStart
    ), 'whole-scrutinee alias replacement lost the original Haxe arm-expression position')

    const stagedNeedle = 'let staged_source_map'
    const stagedGeneratedStart = Buffer.from(rustSource.slice(0, rustSource.indexOf(stagedNeedle))).length
    const stagedSourceStart = Buffer.from(sourceText.slice(0, sourceText.indexOf('var stagedSourceMap:Int;'))).length
    const stagedMappings = mappedFile.mappings.filter(mapping =>
      mapping.nodeKind === 'statement' &&
      mapping.origin.kind === 'haxe-source' &&
      mapping.generated.startByte <= stagedGeneratedStart &&
      mapping.generated.endByte > stagedGeneratedStart
    )
    assert(stagedMappings.some(mapping =>
      mapping.origin.source.startByte <= stagedSourceStart && mapping.origin.source.endByte > stagedSourceStart
    ), 'production statement cleanup did not preserve the original Haxe declaration position')

    const generatedNeedle = 'source-map-value='
    const generatedStart = Buffer.from(rustSource.slice(0, rustSource.indexOf(generatedNeedle))).length
    const sourceStart = Buffer.from(sourceText.slice(0, sourceText.indexOf('trace("source-map-value='))).length
    const matching = mappedFile.mappings.filter(mapping =>
      mapping.origin.kind === 'haxe-source' &&
      mapping.generated.startByte <= generatedStart &&
      mapping.generated.endByte > generatedStart
    )
    assert(matching.length > 0, 'generated trace span did not map to Haxe source')
    assert(matching.some(mapping =>
      mapping.origin.source.startByte <= sourceStart && mapping.origin.source.endByte > sourceStart
    ), 'trace mapping does not contain the exact Haxe trace position')

    const forbiddenRoots = [repoRoot.replaceAll('\\', '/'), root.replaceAll('\\', '/')]
    for (const file of artifact.files) {
      assertPrivatePath(file.generatedFile, 'generated file', forbiddenRoots)
      for (const mapping of file.mappings) {
        assert(Number.isInteger(mapping.originDepth) && mapping.originDepth >= 0,
          'origin depth must be an explicit non-negative tie-breaker')
        if (mapping.origin.kind === 'haxe-source') {
          assertPrivatePath(mapping.origin.source.file, 'Haxe source', forbiddenRoots)
        } else {
          assert.match(mapping.origin.reason, /^[a-z0-9-]+$/,
            'compiler-generated origins need stable machine-readable reasons')
        }
      }
    }

    const cargo = cp.spawnSync('cargo', ['check', '--quiet'], {
      cwd: path.join(root, 'first'),
      encoding: 'utf8',
      env: {...process.env, RUSTFLAGS: '-D warnings'}
    })
    assert.strictEqual(cargo.status, 0, output(cargo))
  } finally {
    fs.rmSync(root, {recursive: true, force: true})
  }

  const ast = fs.readFileSync(astPath, 'utf8')
  for (const constructor of ['ROrigin', 'SOrigin', 'EOrigin']) {
    assert.match(ast, new RegExp(`\\b${constructor}\\(`), `Rust IR must expose ${constructor}`)
  }
  assert.match(fs.readFileSync(printerPath, 'utf8'), /printFileWithSourceMap\s*\(/,
    'the canonical printer must own source-span recording')
  assert(fs.existsSync(sourceMapPath), 'typed source-map codec and lookup contract must exist')

  for (const passName of [
    'NormalizePass.hx',
    'StatementCleanupPass.hx',
    'MutInferencePass.hx',
    'CloneElisionPass.hx',
    'BorrowScopeTighteningPass.hx',
    'MetalRestrictionsPass.hx',
    'NoHxrtPass.hx'
  ]) {
    const source = fs.readFileSync(path.join(passDir, passName), 'utf8')
    assert.match(source, /ROrigin|SOrigin|EOrigin|RustPassTools/,
      `${passName} must explicitly preserve or inspect origin wrappers`)
  }

  console.log('[rust-source-map-test] OK')
}

main()
