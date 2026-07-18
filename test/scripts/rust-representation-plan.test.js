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

function runIn(cwd, command, args) {
  return cp.spawnSync(command, args, { cwd, encoding: 'utf8' })
}

function exactUtf8Span(filePath, needle, fromIndex = 0) {
  const source = fs.readFileSync(filePath, 'utf8')
  const charStart = source.indexOf(needle, fromIndex)
  assert.notStrictEqual(charStart, -1, `source sentinel must remain present: ${needle}`)
  const byteStart = Buffer.byteLength(source.slice(0, charStart), 'utf8')
  return {
    charStart,
    span: `${path.basename(filePath)}:${byteStart}-${byteStart + Buffer.byteLength(needle, 'utf8')}`
  }
}

function cleanOutput(fixture, name) {
  fs.rmSync(path.join(fixture, name), { recursive: true, force: true })
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

  const typedArgs = [
    path.join('node_modules', 'lix', 'bin', 'haxeshim.js'),
    '-cp', 'src',
    '-cp', 'std',
    '-cp', 'test/compiler',
    '-lib', 'reflaxe',
    '-main', 'RustRepresentationTypeFixture',
    '--macro', 'RustRepresentationTypeContractMacro.run()',
    '--no-output'
  ]
  const typedFirst = run(process.execPath, typedArgs)
  assert.strictEqual(typedFirst.status, 0, output(typedFirst))
  const typedSecond = run(process.execPath, typedArgs)
  assert.strictEqual(typedSecond.status, 0, output(typedSecond))
  assert.strictEqual(typedFirst.stdout, typedSecond.stdout, 'typed representation extraction must be byte-for-byte repeatable')
  assert.strictEqual(typedFirst.stderr, typedSecond.stderr, 'typed representation extraction diagnostics must be repeatable')
  assert.deepStrictEqual(typedFirst.stdout.trimEnd().split('\n'), [
    'scalar|scalar|copy_value|not_admitted|copy|haxe_scalar_value|',
    'enumValue|enum_value|owned_value|not_admitted|clone_when_needed|haxe_enum_value|',
    'nativeOwned|native_owned|owned_value|not_admitted|move_once|rust_owned_surface|',
    'sharedIdentity|class_reference|shared_identity|intrinsic|clone_when_needed|haxe_class_identity|object_identity,reference_mutation',
    'polymorphic|polymorphic_reference|shared_trait_object|intrinsic|clone_when_needed|haxe_polymorphic_identity|object_identity,reference_mutation',
    'borrowed|borrowed_ref|borrowed_token|not_admitted|borrow|rust_borrow_surface|',
    'nullableBorrowed|borrowed_ref|borrowed_token|outer_option|borrow|rust_borrow_surface|',
    'nativeHandle|native_handle|native_handle|not_admitted|move_once|rust_native_handle|',
    'dynamicValue|dynamic|dynamic_payload|intrinsic|clone_when_needed|haxe_dynamic_payload|dynamic',
    'stringValue|string|owned_value|not_admitted|clone_when_needed|haxe_string_contract|',
    'arrayValue|array|runtime_array|intrinsic|clone_when_needed|haxe_array_contract|haxe_array_semantics,reference_mutation',
    'anonymousValue|anonymous_object|runtime_anonymous_object|intrinsic|clone_when_needed|haxe_anonymous_object|anonymous_object,object_identity,reference_mutation',
    'functionValue|function_value|shared_function|intrinsic|clone_when_needed|haxe_function_value|function_value,object_identity',
    'iteratorValue|iterator|runtime_iterator|not_admitted|clone_when_needed|haxe_iterator_contract|iterator_semantics,object_identity,reference_mutation',
    'nullableValue|scalar|copy_value|outer_option|copy|haxe_scalar_value|',
    'mapValue|class_reference|shared_identity|intrinsic|clone_when_needed|haxe_class_identity|object_identity,reference_mutation',
    'runtimeString|nullable_string_compat|runtime_string|intrinsic|clone_when_needed|haxe_string_contract|haxe_string_semantics,nullable_compat',
    'function-runtime-v4|object_identity',
    'iterator-runtime-v4|object_identity,reference_mutation',
    'runtime-v4|anonymous_object,dynamic,haxe_array_semantics,object_identity,reference_mutation',
    'no-hxrt|anonymous_object,dynamic,function_value,haxe_array_semantics,iterator_semantics,object_identity,reference_mutation'
  ])

  const controlFixture = path.join(repoRoot, 'test', 'negative', 'representation_dynamic_control')
  const controlOut = path.join(controlFixture, 'out')
  fs.rmSync(controlOut, { recursive: true, force: true })
  const controlArgs = [haxeShim, 'compile.hxml']
  const controlFirst = runIn(controlFixture, process.execPath, controlArgs)
  fs.rmSync(controlOut, { recursive: true, force: true })
  const controlSecond = runIn(controlFixture, process.execPath, controlArgs)
  fs.rmSync(controlOut, { recursive: true, force: true })
  assert.notStrictEqual(controlFirst.status, 0, 'Dynamic control-expression fixture must fail no-hxrt eligibility')
  assert.notStrictEqual(controlSecond.status, 0, 'repeat Dynamic control-expression fixture must fail no-hxrt eligibility')
  assert.strictEqual(output(controlFirst), output(controlSecond), 'Dynamic control-expression diagnostics must be repeatable')
  assert.match(output(controlFirst), /\[HXRS-NO-HXRT-ELIGIBILITY\]/,
    'typed representation decisions must reject Dynamic before the emitted-Rust fallback')
  assert.match(output(controlFirst), /reasonKind `dynamic`/,
    'typed representation rejection must retain the Dynamic semantic reason')
  assert.doesNotMatch(output(controlFirst), /\[HXRS-NO-HXRT-EMITTED-RUNTIME\]/,
    'the late emitted-Rust guard must not own a typed Dynamic value')

  const reportOutA = path.join(controlFixture, 'out_report_a')
  const reportOutB = path.join(controlFixture, 'out_report_b')
  fs.rmSync(reportOutA, { recursive: true, force: true })
  fs.rmSync(reportOutB, { recursive: true, force: true })
  const reportFirst = runIn(controlFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_a'])
  const reportSecond = runIn(controlFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_b'])
  assert.strictEqual(reportFirst.status, 0, output(reportFirst))
  assert.strictEqual(reportSecond.status, 0, output(reportSecond))
  const reportJsonA = fs.readFileSync(path.join(reportOutA, 'runtime_plan.json'), 'utf8')
  const reportJsonB = fs.readFileSync(path.join(reportOutB, 'runtime_plan.json'), 'utf8')
  const reportMarkdownA = fs.readFileSync(path.join(reportOutA, 'runtime_plan.md'), 'utf8')
  const reportMarkdownB = fs.readFileSync(path.join(reportOutB, 'runtime_plan.md'), 'utf8')
  assert.strictEqual(reportJsonA, reportJsonB, 'typed Dynamic runtime-plan JSON must be repeatable')
  assert.strictEqual(reportMarkdownA, reportMarkdownB, 'typed Dynamic runtime-plan Markdown must be repeatable')
  const controlReport = JSON.parse(reportJsonA)
  const dynamicRequirements = controlReport.runtimeRequirements.filter((entry) => entry.reasonKind === 'dynamic')
  assert.strictEqual(dynamicRequirements.length, 1,
    'runtime plan must retain exactly one semantic row for the Dynamic control-expression value')
  const controlSource = fs.readFileSync(path.join(controlFixture, 'Main.hx'), 'utf8')
  const controlNeedle = 'if (flag) 1 else "välue"'
  const controlCharStart = controlSource.indexOf(controlNeedle)
  assert.notStrictEqual(controlCharStart, -1, 'control-expression source sentinel must remain present')
  const controlByteStart = Buffer.byteLength(controlSource.slice(0, controlCharStart), 'utf8')
  const expectedControlSpan = `Main.hx:${controlByteStart}-${controlByteStart + Buffer.byteLength(controlNeedle, 'utf8')}`
  assert.strictEqual(dynamicRequirements[0].sourceKind, 'module')
  assert.strictEqual(dynamicRequirements[0].sourceModule, 'Main')
  assert.strictEqual(dynamicRequirements[0].sourceSpan, expectedControlSpan,
    'runtime plan must attribute Dynamic to the exact source-private control-expression bytes')
  assert.match(reportMarkdownA, new RegExp(expectedControlSpan.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'runtime-plan Markdown must retain the same exact UTF-8 source span as JSON')
  fs.rmSync(reportOutA, { recursive: true, force: true })
  fs.rmSync(reportOutB, { recursive: true, force: true })

  const boundaryFixture = path.join(repoRoot, 'test', 'negative', 'representation_dynamic_boundary')
  cleanOutput(boundaryFixture, 'out')
  const boundaryFirst = runIn(boundaryFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(boundaryFixture, 'out')
  const boundarySecond = runIn(boundaryFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(boundaryFixture, 'out')
  assert.notStrictEqual(boundaryFirst.status, 0, 'concrete-to-Dynamic framework argument must fail no-hxrt eligibility')
  assert.strictEqual(output(boundaryFirst), output(boundarySecond), 'concrete-to-Dynamic diagnostics must be repeatable')
  assert.match(output(boundaryFirst), /\[HXRS-NO-HXRT-ELIGIBILITY\]/,
    'concrete-to-Dynamic boxing must fail at the semantic gate')
  assert.doesNotMatch(output(boundaryFirst), /\[HXRS-NO-HXRT-EMITTED-RUNTIME\]/,
    'concrete-to-Dynamic boxing must not fall through to the emitted-Rust guard')
  const boundarySourcePath = path.join(boundaryFixture, 'Main.hx')
  const boundarySpan = exactUtf8Span(boundarySourcePath, '314159').span
  assert.match(output(boundaryFirst), new RegExp(boundarySpan.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'the semantic Dynamic diagnostic must name the exact concrete argument span')

  cleanOutput(boundaryFixture, 'out_report_a')
  cleanOutput(boundaryFixture, 'out_report_b')
  const boundaryReportFirst = runIn(boundaryFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_a'])
  const boundaryReportSecond = runIn(boundaryFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_b'])
  assert.strictEqual(boundaryReportFirst.status, 0, output(boundaryReportFirst))
  assert.strictEqual(boundaryReportSecond.status, 0, output(boundaryReportSecond))
  const boundaryJsonA = fs.readFileSync(path.join(boundaryFixture, 'out_report_a', 'runtime_plan.json'), 'utf8')
  const boundaryJsonB = fs.readFileSync(path.join(boundaryFixture, 'out_report_b', 'runtime_plan.json'), 'utf8')
  const boundaryMarkdownA = fs.readFileSync(path.join(boundaryFixture, 'out_report_a', 'runtime_plan.md'), 'utf8')
  const boundaryMarkdownB = fs.readFileSync(path.join(boundaryFixture, 'out_report_b', 'runtime_plan.md'), 'utf8')
  assert.strictEqual(boundaryJsonA, boundaryJsonB, 'concrete-to-Dynamic JSON must be repeatable')
  assert.strictEqual(boundaryMarkdownA, boundaryMarkdownB, 'concrete-to-Dynamic Markdown must be repeatable')
  const boundaryDynamic = JSON.parse(boundaryJsonA).runtimeRequirements.filter((entry) => entry.reasonKind === 'dynamic')
  assert.strictEqual(boundaryDynamic.length, 1, 'one concrete Dynamic crossing must produce one semantic requirement')
  assert.strictEqual(boundaryDynamic[0].sourceSpan, boundarySpan,
    'the runtime plan must attribute Dynamic boxing to the concrete argument')
  assert.match(boundaryMarkdownA, new RegExp(boundarySpan.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'concrete-to-Dynamic Markdown must retain the exact crossing span')
  cleanOutput(boundaryFixture, 'out_report_a')
  cleanOutput(boundaryFixture, 'out_report_b')

  const crossingsFixture = path.join(repoRoot, 'test', 'negative', 'representation_dynamic_crossings')
  const crossingsSourcePath = path.join(crossingsFixture, 'Main.hx')
  const crossingSpans = [
    '606060',
    'new BoundaryNode()',
    'BoundaryChoice.Selected',
    '707070',
    '808080',
    '909090',
    'cast(new BoundaryNode(), BoundaryNode)',
    'if (flag) 111111 else 112112',
    'switch (selector) { case 1: 121121; default: 122122; }'
  ].map((needle) => exactUtf8Span(crossingsSourcePath, needle).span)
  cleanOutput(crossingsFixture, 'out')
  const crossingsFirst = runIn(crossingsFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(crossingsFixture, 'out')
  const crossingsSecond = runIn(crossingsFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(crossingsFixture, 'out')
  assert.notStrictEqual(crossingsFirst.status, 0, 'each concrete-to-Dynamic crossing must fail no-hxrt eligibility')
  assert.strictEqual(output(crossingsFirst), output(crossingsSecond), 'concrete crossing diagnostics must be repeatable')
  assert.match(output(crossingsFirst), /\[HXRS-NO-HXRT-ELIGIBILITY\]/)
  assert.doesNotMatch(output(crossingsFirst), /\[HXRS-NO-HXRT-EMITTED-RUNTIME\]/)
  for (const span of crossingSpans)
    assert.match(output(crossingsFirst), new RegExp(span.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      `the no-hxrt diagnostic must name concrete crossing ${span}`)

  cleanOutput(crossingsFixture, 'out_report_a')
  cleanOutput(crossingsFixture, 'out_report_b')
  const crossingsReportFirst = runIn(crossingsFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_a'])
  const crossingsReportSecond = runIn(crossingsFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_b'])
  assert.strictEqual(crossingsReportFirst.status, 0, output(crossingsReportFirst))
  assert.strictEqual(crossingsReportSecond.status, 0, output(crossingsReportSecond))
  const crossingsJsonA = fs.readFileSync(path.join(crossingsFixture, 'out_report_a', 'runtime_plan.json'), 'utf8')
  const crossingsJsonB = fs.readFileSync(path.join(crossingsFixture, 'out_report_b', 'runtime_plan.json'), 'utf8')
  const crossingsMarkdownA = fs.readFileSync(path.join(crossingsFixture, 'out_report_a', 'runtime_plan.md'), 'utf8')
  const crossingsMarkdownB = fs.readFileSync(path.join(crossingsFixture, 'out_report_b', 'runtime_plan.md'), 'utf8')
  assert.strictEqual(crossingsJsonA, crossingsJsonB, 'concrete crossing JSON must be byte-identical')
  assert.strictEqual(crossingsMarkdownA, crossingsMarkdownB, 'concrete crossing Markdown must be byte-identical')
  const crossingDynamicRows = JSON.parse(crossingsJsonA).runtimeRequirements.filter((entry) => entry.reasonKind === 'dynamic')
  for (const span of crossingSpans) {
    assert.strictEqual(crossingDynamicRows.filter((entry) => entry.sourceSpan === span).length, 1,
      `each concrete boundary must produce exactly one Dynamic row at ${span}`)
    assert.match(crossingsMarkdownA, new RegExp(span.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      `Markdown must retain concrete crossing ${span}`)
  }
  cleanOutput(crossingsFixture, 'out_report_a')
  cleanOutput(crossingsFixture, 'out_report_b')

  const collisionFixture = path.join(repoRoot, 'test', 'negative', 'representation_snapshot_collision')
  const collisionSourcePath = path.join(collisionFixture, 'NotWidget.hx')
  const primarySpan = exactUtf8Span(collisionSourcePath, '110011').span
  const secondarySpan = exactUtf8Span(collisionSourcePath, '220022').span
  cleanOutput(collisionFixture, 'out')
  const collisionFirst = runIn(collisionFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(collisionFixture, 'out')
  const collisionSecond = runIn(collisionFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(collisionFixture, 'out')
  assert.notStrictEqual(collisionFirst.status, 0, 'colliding module type names must still fail semantic no-hxrt')
  assert.strictEqual(output(collisionFirst), output(collisionSecond), 'colliding-module diagnostics must be repeatable')
  for (const span of [primarySpan, secondarySpan])
    assert.match(output(collisionFirst), new RegExp(span.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      'both colliding module types must retain their exact evidence')

  cleanOutput(collisionFixture, 'out_report_a')
  cleanOutput(collisionFixture, 'out_report_b')
  const collisionReportFirst = runIn(collisionFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_a'])
  const collisionReportSecond = runIn(collisionFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_b'])
  assert.strictEqual(collisionReportFirst.status, 0, output(collisionReportFirst))
  assert.strictEqual(collisionReportSecond.status, 0, output(collisionReportSecond))
  const collisionJsonA = fs.readFileSync(path.join(collisionFixture, 'out_report_a', 'runtime_plan.json'), 'utf8')
  const collisionJsonB = fs.readFileSync(path.join(collisionFixture, 'out_report_b', 'runtime_plan.json'), 'utf8')
  assert.strictEqual(collisionJsonA, collisionJsonB, 'colliding-module runtime plans must be byte-identical')
  const collisionDynamicSpans = JSON.parse(collisionJsonA).runtimeRequirements
    .filter((entry) => entry.reasonKind === 'dynamic')
    .map((entry) => entry.sourceSpan)
    .sort()
  assert.deepStrictEqual(collisionDynamicSpans, [primarySpan, secondarySpan].sort(),
    'collision-safe typed snapshots must preserve both concrete Dynamic crossings')
  cleanOutput(collisionFixture, 'out_report_a')
  cleanOutput(collisionFixture, 'out_report_b')

  const enumFixture = path.join(repoRoot, 'test', 'positive', 'representation_enum_constructor')
  cleanOutput(enumFixture, 'out')
  const enumFirst = runIn(enumFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(enumFixture, 'out')
  const enumSecond = runIn(enumFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(enumFixture, 'out')
  assert.strictEqual(enumFirst.status, 0, output(enumFirst))
  assert.strictEqual(enumSecond.status, 0, output(enumSecond))
  assert.strictEqual(output(enumFirst), output(enumSecond), 'immediate enum-constructor no-hxrt output must be repeatable')

  cleanOutput(enumFixture, 'out_report_a')
  cleanOutput(enumFixture, 'out_report_b')
  const enumReportFirst = runIn(enumFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_a'])
  const enumReportSecond = runIn(enumFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_b'])
  assert.strictEqual(enumReportFirst.status, 0, output(enumReportFirst))
  assert.strictEqual(enumReportSecond.status, 0, output(enumReportSecond))
  const enumJsonA = fs.readFileSync(path.join(enumFixture, 'out_report_a', 'runtime_plan.json'), 'utf8')
  const enumJsonB = fs.readFileSync(path.join(enumFixture, 'out_report_b', 'runtime_plan.json'), 'utf8')
  assert.strictEqual(enumJsonA, enumJsonB, 'captured enum-constructor runtime plans must be byte-identical')
  const enumSourcePath = path.join(enumFixture, 'Main.hx')
  const immediateCall = exactUtf8Span(enumSourcePath, 'Payload(41)')
  const immediateTargetSpan = exactUtf8Span(enumSourcePath, 'Payload', immediateCall.charStart).span
  const enumObjectRows = JSON.parse(enumJsonA).runtimeRequirements.filter((entry) => entry.reasonKind === 'object_identity')
  assert(enumObjectRows.length > 0, 'an actually captured enum constructor must remain a function-value requirement')
  assert(!enumObjectRows.some((entry) => entry.sourceSpan === immediateTargetSpan),
    'an immediately invoked enum constructor must not be reported as a function value')
  cleanOutput(enumFixture, 'out_report_a')
  cleanOutput(enumFixture, 'out_report_b')

  const operationFixture = path.join(repoRoot, 'test', 'negative', 'representation_no_hxrt_operation')
  const operationSourcePath = path.join(operationFixture, 'Main.hx')
  const firstOperation = exactUtf8Span(operationSourcePath, 'Type.getClassName(Main)').span
  const secondOperationStart = fs.readFileSync(operationSourcePath, 'utf8').indexOf('Type.getClassName(Main)') + 1
  const secondOperation = exactUtf8Span(operationSourcePath, 'Type.getClassName(Main)', secondOperationStart).span
  cleanOutput(operationFixture, 'out')
  const operationFirst = runIn(operationFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(operationFixture, 'out')
  const operationSecond = runIn(operationFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(operationFixture, 'out')
  assert.notStrictEqual(operationFirst.status, 0, 'reflection operations must fail semantic no-hxrt')
  assert.strictEqual(output(operationFirst), output(operationSecond), 'operation diagnostics must be repeatable')
  assert.match(output(operationFirst), /reasonKind `reflection`/)
  for (const span of [firstOperation, secondOperation])
    assert.match(output(operationFirst), new RegExp(span.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      'same-reason operations must retain distinct exact spans')
  assert.match(output(operationFirst), /^Main\.hx:3:/m,
    'the primary semantic diagnostic must point at the first offending expression')

  const mergeFixture = path.join(repoRoot, 'test', 'negative', 'representation_no_hxrt_merge')
  const mergeSourcePath = path.join(mergeFixture, 'Main.hx')
  const exactSysSpan = exactUtf8Span(mergeSourcePath, 'Sys.getCwd()').span
  cleanOutput(mergeFixture, 'out')
  const mergeFirst = runIn(mergeFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(mergeFixture, 'out')
  const mergeSecond = runIn(mergeFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(mergeFixture, 'out')
  assert.notStrictEqual(mergeFirst.status, 0, 'combined Dynamic and platform evidence must fail semantic no-hxrt')
  assert.strictEqual(output(mergeFirst), output(mergeSecond), 'merged no-hxrt diagnostics must be repeatable')
  assert.match(output(mergeFirst), /reasonKind `dynamic`/)
  assert.match(output(mergeFirst), /reasonKind `platform_abstraction`/,
    'an early Dynamic blocker must not suppress later module-path platform evidence')
  for (const modulePath of ['DateTools', 'rust.concurrent.Mutexes', 'Sys'])
    assert.match(output(mergeFirst), new RegExp('from module `' + modulePath.replace(/\./g, '\\.') + '`'),
      `the merged diagnostic must retain platform module ${modulePath}`)
  assert.match(output(mergeFirst), new RegExp(exactSysSpan.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'a platform call that survives in the typed expression tree must retain its exact source span')
  assert.doesNotMatch(output(mergeFirst), /\[HXRS-NO-HXRT-EMITTED-RUNTIME\]/)

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
