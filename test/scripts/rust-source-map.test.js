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
const compilerPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustCompiler.hx')
const printerPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'ast', 'RustASTPrinter.hx')
const sourceMapPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustSourceMap.hx')
const sourceMapSchemaPath = path.join(repoRoot, 'docs', 'schemas', 'rust-source-map-v1.schema.json')
const sourceMapPolicyPath = path.join(repoRoot, 'rust-source-map-policy.json')
const sourceMapPolicyScript = path.join(repoRoot, 'scripts', 'ci', 'rust-source-map-policy.js')
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

function functionSection(source, name, nextName) {
  const start = source.indexOf(`fn ${name}`)
  assert(start >= 0, `generated Rust function ${name} is missing`)
  const end = nextName == null ? source.length : source.indexOf(`fn ${nextName}`, start + 1)
  assert(end > start, `generated Rust function ${name} has no stable end marker`)
  return source.slice(start, end)
}

function occurrenceCount(value, needle) {
  return value.split(needle).length - 1
}

function assertPrivatePath(value, label, forbiddenRoots) {
  assert(!path.isAbsolute(value), `${label} must be relative: ${value}`)
  assert(!value.split(/[\\/]+/).includes('..'), `${label} must not escape its stable root: ${value}`)
  for (const root of forbiddenRoots) {
    assert(!value.includes(root), `${label} leaked a machine-local root: ${value}`)
  }
}

function main() {
  const policyCheck = cp.spawnSync(process.execPath, [sourceMapPolicyScript, '--check'], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
  assert.strictEqual(policyCheck.status, 0, output(policyCheck))
  const schema = JSON.parse(fs.readFileSync(sourceMapSchemaPath, 'utf8'))
  const policy = JSON.parse(fs.readFileSync(sourceMapPolicyPath, 'utf8'))
  assert.deepStrictEqual(schema.$defs.generatedReason.enum,
    policy.generatedReasons.map(reason => reason.id),
    'schema generated-reason vocabulary drifted from rust-source-map-policy.json')
  const validateArtifact = new Ajv({allErrors: true, strict: true}).compile(schema)
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
  const invalidReasonMap = JSON.parse(JSON.stringify(macroMap))
  const generatedOrigin = invalidReasonMap.files.flatMap(file => file.mappings)
    .map(mapping => mapping.origin)
    .find(origin => origin.kind === 'compiler-generated')
  assert(generatedOrigin, 'macro source map must contain a compiler-generated origin for schema mutation')
  generatedOrigin.reason = 'invented-reason'
  assert.strictEqual(validateArtifact(invalidReasonMap), false,
    'the published schema accepted a reason outside the closed compiler-generated vocabulary')

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

  const mutableGuard = runHaxe([
    '-cp', 'src',
    '-cp', 'test/compiler',
    '--macro', 'RustSourceMapContract.printMutableGuardRegression()',
    '--no-output'
  ])
  assert.strictEqual(mutableGuard.status, 0, output(mutableGuard))
  assert.strictEqual(occurrenceCount(mutableGuard.stdout, 'let mut guard_'), 4,
    'origins around the call, callee, receiver, or all three changed mutable-guard inference')
  const mutableGuardRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-source-map-mut-'))
  try {
    const rustc = cp.spawnSync('rustc', [
      '--edition=2021', '-D', 'warnings', '--emit=metadata',
      '-o', path.join(mutableGuardRoot, 'guard.rmeta'), '-'
    ], {
      cwd: mutableGuardRoot,
      encoding: 'utf8',
      input: mutableGuard.stdout
    })
    assert.strictEqual(rustc.status, 0, output(rustc))
  } finally {
    fs.rmSync(mutableGuardRoot, {recursive: true, force: true})
  }

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
    const basicAliasSection = functionSection(rustSource,
      'preserve_whole_option', 'preserve_whole_option_after_effect')
    assert.doesNotMatch(basicAliasSection, /match value\.clone\(\)/,
      'source provenance must not make a direct generic Option switch require T: Clone')
    const effectSection = functionSection(rustSource,
      'preserve_whole_option_after_effect', 'preserve_whole_int_after_payload_use')
    assert.match(effectSection, /mark_alias_effect\(\);[\s\S]*__hx_match_value/,
      'whole-scrutinee aliasing deleted an executable statement before the returned value')
    assert.match(effectSection, /__hx_match_value @ Option::Some\(_\)/,
      'effectful generic Option arm lost clone-free whole-value aliasing')
    assert.doesNotMatch(effectSection, /value\.clone\(\)/,
      'effectful generic Option arm introduced an artificial T: Clone requirement')

    const payloadSection = functionSection(rustSource,
      'preserve_whole_int_after_payload_use', 'preserve_whole_option_with_shadow')
    assert.match(payloadSection, /let payload: i32[\s\S]*__hx_static_set_alias_effect[\s\S]*value/,
      'whole-scrutinee handling deleted a live payload binding or its observable use')

    const shadowSection = functionSection(rustSource,
      'preserve_whole_option_with_shadow', 'preserve_generic_tag_switch_after_effect')
    assert.match(shadowSection, /let value_[0-9]*: Option<T> = Option::None[\s\S]*value_[0-9]*/,
      'a same-named local shadow was collapsed into the outer whole-scrutinee value')

    const genericTagSection = functionSection(rustSource,
      'preserve_generic_tag_switch_after_effect', 'preserve_generic_switch_after_effect')
    assert.match(genericTagSection, /__hx_match_value @ 1[\s\S]*mark_alias_effect\(\);[\s\S]*__hx_match_value/,
      'generic-switch match lowering deleted an effect or failed to preserve its whole-value alias')

    const genericSwitchSection = functionSection(rustSource,
      'preserve_generic_string_switch_after_effect', 'option_value')
    assert.match(genericSwitchSection, /mark_alias_effect\(\);[\s\S]*value/,
      'generic-switch lowering deleted an executable statement before the returned scrutinee')

    const knownSomeSection = functionSection(rustSource, 'known_some_block', 'apply_function')
    assert.match(knownSomeSection, /let next: i32/,
      'known-Some block regression did not exercise preceding block statements')
    assert.doesNotMatch(knownSomeSection, /\.unwrap\(\)/,
      'an origin-wrapped statically present Option tail gained an avoidable unwrap')

    const functionValueSection = functionSection(rustSource, 'block_function_value', 'main')
    assert.strictEqual(occurrenceCount(functionValueSection, 'HxDynRef::new'), 1,
      'an origin-wrapped function-valued block was wrapped in HxDynRef more than once')

    const inheritedSource = fs.readFileSync(
      path.join(root, 'first', 'src', '_main_source_map_string_box.rs'), 'utf8')
    const inheritedSection = functionSection(inheritedSource, 'inherited_block_value', null)
    assert.doesNotMatch(inheritedSection, /HxString::from/,
      'an origin-wrapped inherited specialized String block gained a second representation bridge')
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

    const effectAliasGeneratedStart = Buffer.from(rustSource.slice(0,
      effectSection.indexOf('mark_alias_effect();') + rustSource.indexOf(effectSection) +
      effectSection.slice(effectSection.indexOf('mark_alias_effect();')).indexOf('__hx_match_value'))).length
    const effectSourceMarker = sourceText.indexOf('markAliasEffect();',
      sourceText.indexOf('preserveWholeOptionAfterEffect'))
    const effectAliasSourceStart = Buffer.from(sourceText.slice(0,
      sourceText.indexOf('value;', effectSourceMarker))).length
    assert(mappedFile.mappings.some(mapping =>
      mapping.origin.kind === 'haxe-source' &&
      mapping.generated.startByte <= effectAliasGeneratedStart &&
      mapping.generated.endByte > effectAliasGeneratedStart &&
      mapping.origin.source.startByte <= effectAliasSourceStart &&
      mapping.origin.source.endByte > effectAliasSourceStart
    ), 'effectful whole-scrutinee alias token lost the exact Haxe value-expression position')

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
    const runtime = cp.spawnSync('cargo', ['run', '--quiet'], {
      cwd: path.join(root, 'first'),
      encoding: 'utf8',
      env: {...process.env, RUSTFLAGS: '-D warnings'}
    })
    assert.strictEqual(runtime.status, 0, output(runtime))
    assert.match(runtime.stdout, /source-map-alias=9:5:5:-1:true:1:hit/,
      'whole-scrutinee runtime behavior lost an effect, payload value, shadow, or returned value')
    assert.match(runtime.stdout, /source-map-known-some=5/)
    assert.match(runtime.stdout, /source-map-function=5/)
    assert.match(runtime.stdout, /source-map-inherited=stable/)
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
  const compilerSource = fs.readFileSync(compilerPath, 'utf8')
  assert.strictEqual(occurrenceCount(compilerSource,
    'aliasWholeScrutineeArmExpr(armExpr, scrutineeRustPathName, "__hx_match_value", pat)'), 2,
  'generic-switch and enum-index-switch lowering must share the safe whole-scrutinee rewrite plan')
  const sourceMapSource = fs.readFileSync(sourceMapPath, 'utf8')
  assert.doesNotMatch(sourceMapSource, /Bytes\.ofString\(existing\.code \+ separator\)/,
    'same-file source-map aggregation must not rescan the complete accumulated prefix per chunk')
  assert.match(sourceMapSource, /chunks:Array<String>/,
    'same-file source-map aggregation must retain chunks and join them once')
  assert.match(sourceMapSource,
    /var byteDelta = existing\.byteLength \+ OUTPUT_CHUNK_SEPARATOR_BYTE_LENGTH/,
    'same-file source-map aggregation must shift from its running UTF-8 byte length')
  assert.strictEqual(occurrenceCount(sourceMapSource, 'aggregated.chunks.join('), 1,
    'same-file source-map aggregation must join the accumulated chunks exactly once')

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
