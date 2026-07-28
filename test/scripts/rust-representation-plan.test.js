#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
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

function sourceLine(filePath, needle) {
  return sourceLocation(filePath, needle).line
}

function sourceLocation(filePath, needle) {
  const source = fs.readFileSync(filePath, 'utf8')
  const index = source.indexOf(needle)
  assert.notStrictEqual(index, -1, `source line sentinel must remain present: ${needle}`)
  const lineStart = source.lastIndexOf('\n', index - 1) + 1
  return {
    line: source.slice(0, index).split(/\r?\n/).length,
    // Haxe diagnostics print both endpoints as one-based character columns.
    startColumn: index - lineStart + 1,
    endColumn: index - lineStart + needle.length + 1
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
  const compilerSource = fs.readFileSync(path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustCompiler.hx'), 'utf8')
  const crossingSnapshotSource = fs.readFileSync(
    path.join(repoRoot, 'src', 'reflaxe', 'rust', 'analyze', 'RepresentationAnalysisSnapshot.hx'),
    'utf8')
  assert.strictEqual(compilerSource.split('rustRelativeExpr(["hxrt", "dynamic", "from"])').length - 1, 1,
    'all direct Dynamic::from construction must remain centralized in the labeled compiler-generated String helper')
  assert.match(compilerSource, /function boxCompilerGeneratedStringAsDynamic\(/,
    'compiler-created Dynamic String payloads must retain an explicit audit path')
  assert.match(crossingSnapshotSource, /class RustDynamicCrossingSourceFingerprint/,
    'saved Dynamic actions must receive one opaque source fingerprint built from the actual typed Haxe value')
  assert.doesNotMatch(crossingSnapshotSource,
    /validated\(sourceTypeKey:String,\s*boundaryTypeKey:String,\s*carrierKind:RustSourceValueKind/,
    'saved-action factories must not accept independent type spellings and classifications that can contradict each other')

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
    'classHandle|core_handle|copy_value|intrinsic|copy|haxe_core_handle|',
    'enumHandle|core_handle|copy_value|intrinsic|copy|haxe_core_handle|',
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
  const crossModuleSourcePath = path.join(crossingsFixture, 'CrossModuleBoundary.hx')
  const crossingSpans = [
    '606060',
    'new BoundaryNode()',
    'BoundaryChoice.Selected',
    '707070',
    '808080',
    '909090',
    '101101',
    '102102',
    '131131',
    '132132',
    '133133',
    '141141',
    '142142',
    '151151',
    '161161',
    '162162',
    '163163',
    '164164',
    '169169',
    '165165',
    '166166',
    '167167',
    '168168',
    '171171',
    '172172',
    '181181',
    '191191',
    '192192',
    '201201',
    '202202',
    '208208',
    '209209',
    '204204',
    '205205',
    'cast(new BoundaryNode(), BoundaryNode)',
    'if (flag) 111111 else 112112',
    'switch (selector) { case 1: 121121; default: 122122; }'
	].map((needle) => exactUtf8Span(crossingsSourcePath, needle).span).concat(
		[
			'{value: optionalForDynamic}',
			'dynamicAssigned.value = optionalForDynamic'
		].map((expression) => {
			const outer = exactUtf8Span(crossingsSourcePath, expression)
			return exactUtf8Span(crossingsSourcePath, 'optionalForDynamic', outer.charStart).span
		}),
		['211211', '212212', '213213'].map((needle) => exactUtf8Span(crossModuleSourcePath, needle).span)
	)
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

  // Keep the first generated crate until the shared pinned-Cargo probe below. The action audit proves
  // that analysis and lowering agreed; Cargo then proves the complete assignment/equality/default/
  // replay matrix is valid warning-clean Rust, and running it catches storage-shape mismatches.
  cleanOutput(crossingsFixture, 'out_report_b')

  const directReflectFixture = path.join(repoRoot, 'test', 'snapshot', 'reflect_basic')
  cleanOutput(directReflectFixture, 'out_action_audit')
  const directReflectCompile = runIn(directReflectFixture, process.execPath,
    [haxeShim, 'compile.hxml', '-D', 'rust_no_build', '-D', 'rust_output=out_action_audit', '-D', 'rust_representation_crossing_audit'])
  assert.strictEqual(directReflectCompile.status, 0, output(directReflectCompile))
  const directReflectSource = path.join(directReflectFixture, 'Main.hx')
  const optionalReflectWrite = exactUtf8Span(directReflectSource, 'Reflect.setField(dynamicFields, "value", optionalForDynamic)')
  const directReflectSpans = ['143143', '() -> 170170', '170170'].map((needle) => exactUtf8Span(directReflectSource, needle).span)
    .concat([exactUtf8Span(directReflectSource, 'optionalForDynamic', optionalReflectWrite.charStart).span])
  const directReflectAudit = fs.readFileSync(path.join(directReflectFixture, 'out_action_audit', 'representation_crossing_audit.txt'), 'utf8')
  for (const span of directReflectSpans)
    assert(directReflectAudit.split('\n').some((line) => line.includes(span) && line.includes('|consumed=1|')),
      'constant-name Reflect.setField must consume the saved action for its declared field shape and Dynamic storage')
  cleanOutput(directReflectFixture, 'out_action_audit')
  const crossingsReportFirst = runIn(crossingsFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_a', '-D', 'rust_representation_crossing_audit'])
  const crossingsReportSecond = runIn(crossingsFixture, process.execPath,
    [haxeShim, 'compile.report.hxml', '-D', 'rust_output=out_report_b', '-D', 'rust_representation_crossing_audit'])
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
  for (const needle of ['193193', '194194', '195195', '203203', '206206', '207207']) {
    const unreachableSpan = exactUtf8Span(crossingsSourcePath, needle).span
    assert(!crossingDynamicRows.some((entry) => entry.sourceSpan === unreachableSpan),
      `a boundary after an exhaustive diverging switch must stay absent at ${unreachableSpan}`)
  }
  const crossingAuditA = fs.readFileSync(path.join(crossingsFixture, 'out_report_a', 'representation_crossing_audit.txt'), 'utf8')
  const crossingAuditB = fs.readFileSync(path.join(crossingsFixture, 'out_report_b', 'representation_crossing_audit.txt'), 'utf8')
  assert.strictEqual(crossingAuditA, crossingAuditB, 'saved/consumed Dynamic action record must be byte-identical')
  const userCrossingAudit = crossingAuditA.trim().split('\n').filter((line) => line.startsWith('user|'))
  assert(userCrossingAudit.length > 0, 'the Dynamic crossing contract must save user-authored lowering actions')
  assert(userCrossingAudit.every((line) => line.includes('|consumed=1|')),
    'every saved user-authored Dynamic action must be consumed exactly once')
  for (const span of crossingSpans)
    assert(userCrossingAudit.some((line) => line.includes(`|boundary=${span}|`) && line.includes('|consumed=1|')),
      `each intended Dynamic source boundary must consume a saved action at ${span}`)
  for (const replay of [
    ...['171171', '172172', '181181', '191191', '192192'].map((needle) => ({ source: crossingsSourcePath, needle })),
    ...['211211', '212212', '213213'].map((needle) => ({ source: crossModuleSourcePath, needle }))
  ]) {
    const replaySpan = exactUtf8Span(replay.source, replay.needle).span
    assert(userCrossingAudit.some((line) => line.includes(replaySpan) && line.includes('|replayed=1|')
      && /\|replay-family=[^|]+\|/.test(line) && !line.includes('|replay-family=none|')),
      `${replay.needle} must record its second generated emission as one explicit replay`)
  }
  assert(userCrossingAudit.every((line) => /\|reuse=(?:copy|clone_when_needed|move_once|borrow)\|/.test(line)),
    'every saved Dynamic action must expose the reuse policy that lowering consumes')
  for (const expected of [
    { needle: '606060', reuse: 'copy' },
    { needle: 'new BoundaryNode()', reuse: 'clone_when_needed' },
    { needle: 'BoundaryChoice.Selected', reuse: 'clone_when_needed' }
  ]) {
    const span = exactUtf8Span(crossingsSourcePath, expected.needle).span
    assert(userCrossingAudit.some((line) => line.includes(span) && line.includes(`|reuse=${expected.reuse}|`)),
      `${expected.needle} must retain its saved ${expected.reuse} policy through lowering`)
  }
  for (const needle of ['trace(node)', 'Std.string(node)', 'throw node']) {
    const expressionSpan = exactUtf8Span(crossingsSourcePath, needle)
    const nodeSpan = exactUtf8Span(crossingsSourcePath, 'node', expressionSpan.charStart).span
    assert(userCrossingAudit.some((line) => line.includes(nodeSpan)),
      `${needle} must route its user value through the saved Dynamic action`)
  }
	cleanOutput(crossingsFixture, 'out_report_b')

  const unreachableCrossingFixture = path.join(repoRoot, 'test', 'snapshot', 'return_void')
  cleanOutput(unreachableCrossingFixture, 'out')
  const unreachableCrossingCompile = runIn(unreachableCrossingFixture, process.execPath,
    [haxeShim, 'compile.hxml', '-D', 'rust_no_build'])
  assert.strictEqual(unreachableCrossingCompile.status, 0, output(unreachableCrossingCompile))
  const unreachableCrossingRust = fs.readFileSync(path.join(unreachableCrossingFixture, 'out', 'src', 'main.rs'), 'utf8')
  assert.doesNotMatch(unreachableCrossingRust, /nope/,
    'early representation analysis must not save an action for code lowering removes after an unconditional return')
  cleanOutput(unreachableCrossingFixture, 'out')

  const staticTypeCheckFixture = path.join(repoRoot, 'test', 'snapshot', 'std_is_of_type')
  cleanOutput(staticTypeCheckFixture, 'out')
  const staticTypeCheckCompile = runIn(staticTypeCheckFixture, process.execPath,
    [haxeShim, 'compile.hxml', '-D', 'rust_no_build'])
  assert.strictEqual(staticTypeCheckCompile.status, 0, output(staticTypeCheckCompile))
  cleanOutput(staticTypeCheckFixture, 'out')

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
  const immediateTargetNeedles = ['Payload(41)', '(Payload)(42)', 'Token.Payload(43)', 'GenericToken.Wrapped(44)',
    '(@:noCompletion Payload)(45)', '(cast Payload : Int->Token)(46)']
  const immediateTargetSpans = immediateTargetNeedles.map((needle) => {
    const call = exactUtf8Span(enumSourcePath, needle)
    const targetNeedle = needle.includes('Wrapped') ? 'Wrapped' : 'Payload'
    return exactUtf8Span(enumSourcePath, targetNeedle, call.charStart).span
  })
  const enumObjectRows = JSON.parse(enumJsonA).runtimeRequirements.filter((entry) => entry.reasonKind === 'object_identity')
  assert(enumObjectRows.length > 0, 'an actually captured enum constructor must remain a function-value requirement')
  assert(!enumObjectRows.some((entry) => entry.sourceSpan === immediateTargetSpan),
    'an immediately invoked enum constructor must not be reported as a function value')
  for (const span of immediateTargetSpans)
    assert(!enumObjectRows.some((entry) => entry.sourceSpan === span),
      `transparent wrappers around an immediately invoked enum constructor must not materialize a function value at ${span}`)
  const storedConstructorNeedles = [
    'var constructor = Payload;',
    'keepConstructor(Payload)',
    'return Payload;'
  ]
  for (const needle of storedConstructorNeedles) {
    const expression = exactUtf8Span(enumSourcePath, needle)
    const targetSpan = exactUtf8Span(enumSourcePath, 'Payload', expression.charStart).span
    assert(enumObjectRows.some((entry) => entry.sourceSpan === targetSpan),
      `capturing, passing, or returning an enum constructor must retain a real function-value row at ${targetSpan}`)
  }
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

  const platformPositionFixture = path.join(repoRoot, 'test', 'negative', 'representation_no_hxrt_platform_position')
  const platformPositionSource = path.join(platformPositionFixture, 'Main.hx')
  const sysNeedle = 'Sys.getEnv("κλειδί")'
  const sysLocation = sourceLocation(platformPositionSource, sysNeedle)
  const sysLine = sysLocation.line
  const sysSpan = exactUtf8Span(platformPositionSource, sysNeedle).span
  cleanOutput(platformPositionFixture, 'out')
  const platformPositionFirst = runIn(platformPositionFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(platformPositionFixture, 'out')
  const platformPositionSecond = runIn(platformPositionFixture, process.execPath, [haxeShim, 'compile.hxml'])
  cleanOutput(platformPositionFixture, 'out')
  assert.notStrictEqual(platformPositionFirst.status, 0, 'a Sys operation must fail semantic no-hxrt')
  assert.strictEqual(output(platformPositionFirst), output(platformPositionSecond), 'platform diagnostics must be repeatable')
  assert.match(output(platformPositionFirst),
    new RegExp(`^Main\\.hx:${sysLine}: characters ${sysLocation.startColumn}-${sysLocation.endColumn} :`, 'm'),
    'a broad Sys module row must not preempt the exact Sys.getEnv expression range')
  assert.match(output(platformPositionFirst), new RegExp(sysSpan.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'the stored Sys range must count multibyte text inside the blocked expression as UTF-8 bytes')

  for (const operation of [
    { define: 'position_date_tools', needle: 'DateTools.parse(86400000)', module: 'DateTools' },
    { define: 'position_concurrent', needle: 'rust.concurrent.Mutexes.create(1)', module: 'rust.concurrent.Mutexes' }
  ]) {
    cleanOutput(platformPositionFixture, 'out')
    const firstOperation = runIn(platformPositionFixture, process.execPath, [haxeShim, 'compile.hxml', '-D', operation.define])
    cleanOutput(platformPositionFixture, 'out')
    const secondOperation = runIn(platformPositionFixture, process.execPath, [haxeShim, 'compile.hxml', '-D', operation.define])
    cleanOutput(platformPositionFixture, 'out')
    assert.notStrictEqual(firstOperation.status, 0, `${operation.module} must fail semantic no-hxrt`)
    assert.strictEqual(output(firstOperation), output(secondOperation), `${operation.module} diagnostics must be repeatable`)
    const location = sourceLocation(platformPositionSource, operation.needle)
    assert.match(output(firstOperation),
      new RegExp(`^Main\\.hx:${location.line}: characters ${location.startColumn}-${location.endColumn} :`, 'm'),
      `the broad ${operation.module} module row must not preempt its exact operation range`)
    const span = exactUtf8Span(platformPositionSource, operation.needle).span
    assert.match(output(firstOperation), new RegExp(span.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      `${operation.module} must retain its exact typed-operation byte range`)
  }

  const absolutePlatformArgs = [haxeShim,
    '-cp', platformPositionFixture,
    '-lib', 'reflaxe.rust',
    '-D', 'reflaxe_rust_profile=metal',
    '-D', 'rust_no_hxrt',
    '-D', 'rust_no_build',
    '-D', 'rust_output=test/negative/representation_no_hxrt_platform_position/out',
    '-main', 'Main']
  const absolutePlatform = run(process.execPath, absolutePlatformArgs)
  cleanOutput(platformPositionFixture, 'out')
  assert.notStrictEqual(absolutePlatform.status, 0, 'absolute classpaths must preserve the no-hxrt failure')
  assert.doesNotMatch(output(absolutePlatform), new RegExp(repoRoot.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'no-runtime diagnostics must not expose the machine-local checkout path')
  assert.match(output(absolutePlatform),
    new RegExp(`^(?:[^:\\n]+\\/)*Main\\.hx:${sysLine}: characters ${sysLocation.startColumn}-${sysLocation.endColumn} :`, 'm'),
    'a private source identity from an absolute classpath must still recover the exact expression range')
  assert.match(output(absolutePlatform), new RegExp(sysSpan.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
    'an absolute classpath must preserve the multibyte expression byte range without exposing the real path')

  const externalClasspath = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-position-'))
  try {
    fs.copyFileSync(platformPositionSource, path.join(externalClasspath, 'Main.hx'))
    const externalPlatform = run(process.execPath, [haxeShim,
      '-cp', externalClasspath,
      '-lib', 'reflaxe.rust',
      '-D', 'reflaxe_rust_profile=metal',
      '-D', 'rust_no_hxrt',
      '-D', 'rust_no_build',
      '-D', `rust_output=${path.join(externalClasspath, 'out')}`,
      '-main', 'Main'])
    assert.notStrictEqual(externalPlatform.status, 0, 'an external absolute classpath must preserve the no-hxrt failure')
    assert.doesNotMatch(output(externalPlatform), new RegExp(externalClasspath.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      'diagnostics must not expose the external absolute classpath')
    assert.match(output(externalPlatform),
      new RegExp(`\\[HXRS-NO-HXRT-ELIGIBILITY\\] Main\\.hx:${sysLine}: characters ${sysLocation.startColumn}-${sysLocation.endColumn} :`),
      'the diagnostic text must retain the exact private expression range when Haxe cannot safely own the external filename')
    assert.doesNotMatch(output(externalPlatform), /^Main\.hx:1: characters/m,
      'the outer Haxe position must be unknown instead of inventing a line-one range for an external source')
    assert.match(output(externalPlatform), new RegExp(sysSpan.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      'external-classpath diagnostics must retain the exact multibyte byte range')
  } finally {
    fs.rmSync(externalClasspath, { recursive: true, force: true })
  }

  for (const externalCase of [
    { main: 'ExternalThrow', needle: 'throw "βλάβη"' },
    { main: 'ExternalTry', needle: 'try {\n\t\t\tthrow "σφάλμα";\n\t\t} catch (_:String) {}' }
  ]) {
    const source = path.join(platformPositionFixture, `${externalCase.main}.hx`)
    const location = sourceLocation(source, externalCase.needle)
    const span = exactUtf8Span(source, externalCase.needle).span
    const externalRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-position-'))
    try {
      fs.copyFileSync(source, path.join(externalRoot, `${externalCase.main}.hx`))
      const result = run(process.execPath, [haxeShim,
        '-cp', externalRoot,
        '-lib', 'reflaxe.rust',
        '-D', 'reflaxe_rust_profile=metal',
        '-D', 'rust_no_hxrt',
        '-D', 'rust_no_build',
        '-D', `rust_output=${path.join(externalRoot, 'out')}`,
        '-main', externalCase.main])
      assert.notStrictEqual(result.status, 0, `${externalCase.main} must fail the early no-hxrt check`)
      assert.match(output(result), /\[HXRS-NO-HXRT-ELIGIBILITY\]/,
        `${externalCase.main} must be rejected before generated Rust becomes the ordinary detector`)
      assert.doesNotMatch(output(result), new RegExp(externalRoot.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
        `${externalCase.main} diagnostics must not expose its absolute classpath`)
      const displayLocation = externalCase.needle.includes('\n')
        ? `${externalCase.main}\\.hx: lines ${location.line}-${location.line + externalCase.needle.split('\n').length - 1}`
        : `${externalCase.main}\\.hx:${location.line}: characters ${location.startColumn}-`
      assert.match(output(result), new RegExp(`\\[HXRS-NO-HXRT-ELIGIBILITY\\] ${displayLocation}`),
        `${externalCase.main} must retain the exact external expression line and starting column`)
      assert.match(output(result), new RegExp(span.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
        `${externalCase.main} must retain the operation's private UTF-8 byte range`)
    } finally {
      fs.rmSync(externalRoot, { recursive: true, force: true })
    }
  }

  const castCallSource = path.join(platformPositionFixture, 'ExternalCastCalls.hx')
  const castCallNeedles = [
    '(cast Sys.time : Void->Float)()',
    '(cast Type.resolveClass : String->Class<Dynamic>)("β.ExternalCastCalls")',
    '(cast Reflect.field : Dynamic->String->Dynamic)({value: 1}, "κλειδί")'
  ]
  const castCallRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-cast-call-position-'))
  try {
    fs.copyFileSync(castCallSource, path.join(castCallRoot, 'ExternalCastCalls.hx'))
    const castCallResult = run(process.execPath, [haxeShim,
      '-cp', castCallRoot,
      '-lib', 'reflaxe.rust',
      '-D', 'reflaxe_rust_profile=metal',
      '-D', 'rust_no_hxrt',
      '-D', 'rust_no_build',
      '-D', `rust_output=${path.join(castCallRoot, 'out')}`,
      '-main', 'ExternalCastCalls'])
    assert.notStrictEqual(castCallResult.status, 0,
      'same-type casts around Sys, Type, and Reflect targets must fail the early no-hxrt check')
    assert.match(output(castCallResult), /\[HXRS-NO-HXRT-ELIGIBILITY\]/,
      'cast-wrapped runtime operations must be rejected before Rust AST construction')
    assert.doesNotMatch(output(castCallResult), /\[HXRS-NO-HXRT-EMITTED-RUNTIME\]/,
      'the generated-Rust guard must remain a backstop rather than the ordinary cast-wrapped detector')
    assert.doesNotMatch(output(castCallResult),
      new RegExp(castCallRoot.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      'cast-wrapped operation diagnostics must not expose their absolute classpath')
    const primaryCastLocation = sourceLocation(castCallSource, castCallNeedles[0])
    assert.match(output(castCallResult),
      new RegExp(`\\[HXRS-NO-HXRT-ELIGIBILITY\\] ExternalCastCalls\\.hx:${primaryCastLocation.line}:`),
      'the first canonical cast-wrapped operation must own the primary exact constructor location')
    for (const needle of castCallNeedles) {
      const span = exactUtf8Span(castCallSource, needle).span
      assert.match(output(castCallResult), new RegExp(span.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
        `${needle} must retain its exact private UTF-8 source range`)
    }
  } finally {
    fs.rmSync(castCallRoot, { recursive: true, force: true })
  }

  const unsupportedBorrowFixture = path.join(repoRoot, 'test', 'negative', 'representation_borrow_dynamic_unsupported')
  for (const unsupported of [
    { main: 'NativeBorrow', detail: 'native handle' },
    { main: 'GenericBorrow', detail: 'generic inner type' }
  ]) {
    const source = path.join(unsupportedBorrowFixture, `${unsupported.main}.hx`)
    const line = sourceLine(source, 'inspect(borrowed)')
    const outputName = `out_${unsupported.main}`
    const compile = () => runIn(unsupportedBorrowFixture, process.execPath, [haxeShim,
      '-cp', '.',
      '-lib', 'reflaxe.rust',
      '-D', 'reflaxe_rust_profile=metal',
      '-D', 'rust_no_build',
      '-D', `rust_output=${outputName}`,
      '-main', unsupported.main])
    cleanOutput(unsupportedBorrowFixture, outputName)
    const firstUnsupported = compile()
    cleanOutput(unsupportedBorrowFixture, outputName)
    const secondUnsupported = compile()
    assert.notStrictEqual(firstUnsupported.status, 0, `${unsupported.main} must be rejected before Rust construction`)
    assert.strictEqual(output(firstUnsupported), output(secondUnsupported), `${unsupported.main} diagnostics must be repeatable`)
    assert.match(output(firstUnsupported), /\[HXRS-BORROW-REGION\].*cannot enter Dynamic/,
      `${unsupported.main} must explain why its borrowed value cannot become owned Dynamic storage`)
    assert.match(output(firstUnsupported), new RegExp(`${unsupported.main}\\.hx:${line}:`),
      `${unsupported.main} must point to the exact failing call`)
    assert.match(output(firstUnsupported), new RegExp(unsupported.detail),
      `${unsupported.main} must name the concrete unsupported reason`)
    assert.doesNotMatch(output(firstUnsupported), /Internal Rust representation error/,
      `${unsupported.main} must fail during typed analysis instead of later Rust lowering`)
    assert(!fs.existsSync(path.join(unsupportedBorrowFixture, outputName, 'src')),
      `${unsupported.main} must not construct Rust source after the typed boundary fails`)
    cleanOutput(unsupportedBorrowFixture, outputName)
  }

  const anonymousBorrowFixture = path.join(repoRoot, 'test', 'negative', 'representation_anonymous_borrowed_field')
  for (const operation of ['literal', 'assign', 'reflect']) {
    for (const nullable of [false, true]) {
      const outputName = `out_${operation}_${nullable ? 'nullable' : 'direct'}`
      const args = [haxeShim, 'compile.hxml', '-D', `operation_${operation}`, '-D', `rust_output=${outputName}`]
      if (nullable)
        args.push('-D', 'nullable')
      const compile = () => runIn(anonymousBorrowFixture, process.execPath, args)
      cleanOutput(anonymousBorrowFixture, outputName)
      const firstRejected = compile()
      cleanOutput(anonymousBorrowFixture, outputName)
      const secondRejected = compile()
      assert.notStrictEqual(firstRejected.status, 0,
        `${operation} storage for ${nullable ? 'Null<rust.Ref<T>>' : 'rust.Ref<T>'} anonymous fields must fail early`)
      assert.strictEqual(output(firstRejected), output(secondRejected),
        `${operation} borrowed-field diagnostics must be repeatable`)
      assert.match(output(firstRejected), /\[HXRS-BORROW-REGION\].*anonymous field `value`/,
        `${operation} storage must explain that a runtime anonymous object cannot expose rust.Ref<T>`)
      assert.match(output(firstRejected), /store an owned value/i,
        `${operation} storage must tell the author how to make the field safe`)
      assert.doesNotMatch(output(firstRejected), /Internal Rust representation error/,
        `${operation} storage must fail during typed analysis rather than Rust lowering`)
      assert(!fs.existsSync(path.join(anonymousBorrowFixture, outputName, 'src')),
        `${operation} storage must not construct Rust source after the typed boundary fails`)
      cleanOutput(anonymousBorrowFixture, outputName)
    }
  }
  const anonymousBorrowSource = path.join(anonymousBorrowFixture, 'Main.hx')
  const optionalShapeLine = sourceLine(anonymousBorrowSource, 'var holder:BorrowedHolder = {};')
  for (const operation of ['runtime_reflect', 'dynamic_reflect']) {
    const outputName = `out_${operation}_optional_nullable`
    const args = [haxeShim, 'compile.hxml',
      '-D', 'reflaxe_rust_profile=portable',
      '-D', `operation_${operation}`,
      '-D', 'optional',
      '-D', 'nullable',
      '-D', `rust_output=${outputName}`]
    const compile = () => runIn(anonymousBorrowFixture, process.execPath, args)
    cleanOutput(anonymousBorrowFixture, outputName)
    const firstRejected = compile()
    cleanOutput(anonymousBorrowFixture, outputName)
    const secondRejected = compile()
    assert.notStrictEqual(firstRejected.status, 0,
      `${operation} must reject an omitted optional Null<rust.Ref<T>> field before reflection can mutate it`)
    assert.strictEqual(output(firstRejected), output(secondRejected),
      `${operation} optional borrowed-field diagnostics must be repeatable`)
    assert.match(output(firstRejected), /\[HXRS-BORROW-REGION\].*anonymous field `value`/,
      `${operation} must explain that the declared runtime record shape cannot expose rust.Ref<T>`)
    assert.match(output(firstRejected), new RegExp(`Main\\.hx:${optionalShapeLine}:`),
      `${operation} must point to the anonymous value whose complete declared shape is unsupported`)
    assert.match(output(firstRejected), /store an owned value/i,
      `${operation} must tell the author how to make the field safe`)
    assert(!fs.existsSync(path.join(anonymousBorrowFixture, outputName, 'src')),
      `${operation} must stop before generated Rust can store an owned value under a borrowed field type`)
    cleanOutput(anonymousBorrowFixture, outputName)
  }
  const controlShapeLine = sourceLine(anonymousBorrowSource, 'var erased:Dynamic = flag ? holder : holder;')
  const controlOutputName = 'out_dynamic_control_optional_nullable'
  const anonymousControlArgs = [haxeShim, 'compile.hxml',
    '-D', 'reflaxe_rust_profile=portable',
    '-D', 'operation_dynamic_control',
    '-D', 'optional',
    '-D', 'nullable',
    '-D', `rust_output=${controlOutputName}`]
  cleanOutput(anonymousBorrowFixture, controlOutputName)
  const rejectedControlShape = runIn(anonymousBorrowFixture, process.execPath, anonymousControlArgs)
  assert.notStrictEqual(rejectedControlShape.status, 0,
    'each typed anonymous branch entering Dynamic must reject the complete borrowed-field shape')
  assert.match(output(rejectedControlShape), /\[HXRS-BORROW-REGION\].*anonymous field `value`/,
    'contextual control crossings must retain the unsupported anonymous field declaration')
  assert.match(output(rejectedControlShape), new RegExp(`Main\\.hx:${controlShapeLine}:`),
    'the control crossing must point to the typed anonymous value before its shape is erased')
  assert(!fs.existsSync(path.join(anonymousBorrowFixture, controlOutputName, 'src')),
    'the control crossing must stop before Rust construction')
  cleanOutput(anonymousBorrowFixture, controlOutputName)

  const borrowDynamicFixture = path.join(repoRoot, 'test', 'positive', 'representation_borrow_dynamic')
  cleanOutput(borrowDynamicFixture, 'out')
  const borrowDynamicCompile = runIn(borrowDynamicFixture, process.execPath, [haxeShim, 'compile.hxml'])
  assert.strictEqual(borrowDynamicCompile.status, 0, output(borrowDynamicCompile))
  const borrowDynamicRust = fs.readFileSync(path.join(borrowDynamicFixture, 'out', 'src', 'main.rs'), 'utf8')
  assert.match(borrowDynamicRust, /hxrt::dynamic::from\(\*borrowed\)/,
    'a Copy value behind rust.Ref must be dereferenced before it enters Dynamic')
  assert.match(borrowDynamicRust, /hxrt::dynamic::from\(\(\*borrowed_2\)\.clone\(\)\)/,
    'a Clone value behind rust.Ref must be cloned as an owned value before it enters Dynamic')
  assert.match(borrowDynamicRust, /hxrt::dynamic::from\(\(\*borrowed_3\)\.clone\(\)\)/,
    'a concrete rust.Vec behind rust.Ref must be cloned as an owned value before it enters Dynamic')
  assert.match(borrowDynamicRust, /hxrt::dynamic::from\(\(\*borrowed_4\)\.clone\(\)\)/,
    'a concrete rust.PathBuf behind rust.Ref must be cloned as an owned value before it enters Dynamic')
  assert.doesNotMatch(borrowDynamicRust, /hxrt::dynamic::from\(borrowed(?:_[0-9]+)?\)/,
    'the short-lived Rust borrow token itself must never enter Dynamic')
  const borrowAudit = fs.readFileSync(path.join(borrowDynamicFixture, 'out', 'representation_crossing_audit.txt'), 'utf8')
  assert.match(borrowAudit, /\|borrow-copy\|reuse=copy\|consumed=1\|/)
  assert.match(borrowAudit, /\|borrow-clone\|reuse=clone_when_needed\|consumed=1\|/)
  const rustcProbe = run('rustc', ['--print', 'sysroot'])
  assert.strictEqual(rustcProbe.status, 0, output(rustcProbe))
  const cargoBin = path.join(rustcProbe.stdout.trim(), 'bin', process.platform === 'win32' ? 'cargo.exe' : 'cargo')
  const crossingsCargoCheck = runIn(path.join(crossingsFixture, 'out_report_a'), cargoBin, ['check', '--quiet'])
  assert.strictEqual(crossingsCargoCheck.status, 0, output(crossingsCargoCheck))
  const crossingsCargoRun = runIn(path.join(crossingsFixture, 'out_report_a'), cargoBin, ['run', '--quiet'])
  assert.strictEqual(crossingsCargoRun.status, 0, output(crossingsCargoRun))
  cleanOutput(crossingsFixture, 'out_report_a')
  const borrowCargoCheck = runIn(path.join(borrowDynamicFixture, 'out'), cargoBin, ['check', '--quiet'])
  assert.strictEqual(borrowCargoCheck.status, 0, output(borrowCargoCheck))
  const borrowCargoRun = runIn(path.join(borrowDynamicFixture, 'out'), cargoBin, ['run', '--quiet'])
  assert.strictEqual(borrowCargoRun.status, 0, output(borrowCargoRun))
  assert.strictEqual(borrowCargoRun.stdout.trim(), '7|hello|true', 'owned borrow snapshots must not escape the Borrow callback')
  cleanOutput(borrowDynamicFixture, 'out')

  const frameworkDynamicFixture = path.join(repoRoot, 'test', 'snapshot', 'haxe_crypto_smoke')
  const frameworkDynamicBuild = run('bash', ['test/run-snapshots.sh', '--case', 'haxe_crypto_smoke', '--no-diff'])
  assert.strictEqual(frameworkDynamicBuild.status, 0, output(frameworkDynamicBuild))
  const serializerRust = fs.readFileSync(path.join(frameworkDynamicFixture, 'out', 'src', 'haxe_serializer.rs'), 'utf8')
  const unserializerRust = fs.readFileSync(path.join(frameworkDynamicFixture, 'out', 'src', 'haxe_unserializer.rs'), 'utf8')
  assert.match(serializerRust, /hxrt::dynamic::from_ref\(v\.clone\(\)\)/,
    'framework-authored Dynamic conversions must preserve a shared value reused by a later loop iteration')
	  assert.match(unserializerRust, /hxrt::dynamic::from_ref\(o\.clone\(\)\)/,
	    'a framework-authored loop must clone its reusable object handle before Dynamic consumes it')
	  cleanOutput(frameworkDynamicFixture, 'out')

	  for (const semanticCase of ['dynamic_access_iterator_boundary', 'map_key_value_iterator_manual']) {
	    const frameworkGenericRun = run('python3', ['test/run-semantic-diff.py', '--case', semanticCase])
	    assert.strictEqual(frameworkGenericRun.status, 0,
	      `${semanticCase} must admit only its reviewed framework generic Dynamic boundary\n${output(frameworkGenericRun)}`)
	  }

	  const nullableMutableFixture = path.join(repoRoot, 'test', 'snapshot', 'rust_borrow_ref')
  cleanOutput(nullableMutableFixture, 'out')
  const nullableMutableCompile = runIn(nullableMutableFixture, process.execPath, [haxeShim, 'compile.hxml'])
  assert.strictEqual(nullableMutableCompile.status, 0, output(nullableMutableCompile))
  const nullableMutableRust = fs.readFileSync(path.join(nullableMutableFixture, 'out', 'src', 'main.rs'), 'utf8')
  assert.doesNotMatch(nullableMutableRust, /let __hx_opt = if choose_first/,
    'a nullable mutable-reference control expression must not move its Option local into a temporary')
  assert.match(nullableMutableRust, /consume_mut_ref\(if choose_first \{ match &mut maybe/,
    'if branches must reborrow the nullable mutable reference at their result leaves')
  assert.match(nullableMutableRust, /if score == 4 \{ match &mut maybe/,
    'switch result branches must reborrow without consuming the original Option binding')
  assert.doesNotMatch(nullableMutableRust, /let __hx_opt = match branch/,
    'an exhaustive enum switch must reborrow each branch instead of moving the nullable mutable reference')
  assert.doesNotMatch(nullableMutableRust, /let __hx_opt = match diverging_branch/,
    'an exhaustive switch with a diverging arm must not move the nullable mutable-reference Option')
  assert.doesNotMatch(nullableMutableRust, /let __hx_opt = match diverging_bool/,
    'an exhaustive Bool switch with a diverging arm must not move the nullable mutable-reference Option')
  assert.match(nullableMutableRust, /match diverging_branch \{[\s\S]*?match &mut maybe[\s\S]*?hxrt::exception::throw/,
    'the enum switch must reborrow its local arm and preserve its throwing arm')
  assert.match(nullableMutableRust, /if diverging_bool \{[\s\S]*?match &mut maybe[\s\S]*?hxrt::exception::throw/,
    'the Bool switch must reborrow its local arm and preserve its throwing arm')
  assert.match(nullableMutableRust, /observe_score\(score\);\s+match &mut maybe/,
    'block statements must remain before the reborrowed tail expression')
  assert.doesNotMatch(nullableMutableRust, /maybe(?:_3)?\.clone\(\)/,
    'Option<&mut T> and Option<&mut [T]> must never be cloned')
  const nullableMutableRun = runIn(path.join(nullableMutableFixture, 'out'), cargoBin, ['run', '--quiet'])
  assert.strictEqual(nullableMutableRun.status, 0, output(nullableMutableRun))
  assert.strictEqual(nullableMutableRun.stdout.trim(), 'true',
    'conditional nullable mutable reborrows must preserve every later use at runtime')
  cleanOutput(nullableMutableFixture, 'out')

  const mergeFixture = path.join(repoRoot, 'test', 'negative', 'representation_no_hxrt_merge')
  const mergeSourcePath = path.join(mergeFixture, 'Main.hx')
  const exactPlatformSpans = [
    exactUtf8Span(mergeSourcePath, 'DateTools.parse(86400000)').span,
    exactUtf8Span(mergeSourcePath, 'rust.concurrent.Mutexes.create(1)').span,
    exactUtf8Span(mergeSourcePath, 'Sys.getCwd()').span
  ]
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
  for (const span of exactPlatformSpans)
    assert.match(output(mergeFirst), new RegExp(span.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      'captured platform operations must retain their independent exact source spans')
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
