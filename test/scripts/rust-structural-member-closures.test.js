#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const haxeShim = path.join(repoRoot, 'node_modules', 'lix', 'bin', 'haxeshim.js')
const astPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'ast', 'RustAST.hx')
const compilerPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustCompiler.hx')
const harnessPath = path.join(repoRoot, 'scripts', 'ci', 'harness.sh')
const passDir = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'passes')

function runHaxe(args) {
  return cp.spawnSync(process.execPath, [haxeShim, ...args], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
}

function output(result) {
  return `${result.stdout || ''}\n${result.stderr || ''}`
}

function compileLegacyFixture(root, name, expression, expectedType) {
  const fixtureDir = path.join(root, name)
  fs.mkdirSync(fixtureDir, { recursive: true })
  fs.writeFileSync(path.join(fixtureDir, 'Main.hx'), `
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustPath;
class Main {
  static function main():Void {
    ${expression}
  }
}
`)
  const result = runHaxe(['-cp', 'src', '-cp', fixtureDir, '-main', 'Main', '--no-output'])
  assert.notStrictEqual(result.status, 0, `${name} must reject the legacy string payload`)
  assert.match(output(result), expectedType, `${name} must identify its structural replacement type`)
}

function main() {
  assert.match(
    fs.readFileSync(harnessPath, 'utf8'),
    /structural Rust member and closure contract" npm run test:rust-structural-member-closures/,
    'the full harness must run the structural member/closure contract'
  )

  const args = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '-main', 'RustStructuralMemberClosureContract',
    '--interp'
  ]
  const first = runHaxe(args)
  assert.strictEqual(first.status, 0, output(first))
  const second = runHaxe(args)
  assert.strictEqual(second.status, 0, output(second))
  assert.strictEqual(first.stdout, second.stdout, 'member/closure printer bytes must be repeatable')
  assert.strictEqual(first.stderr, second.stderr, 'member/closure diagnostics must be repeatable')

  const cloneShadowArgs = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '--macro', 'RustCloneShadowingContract.run()',
    '--no-output'
  ]
  const firstCloneShadow = runHaxe(cloneShadowArgs)
  assert.strictEqual(firstCloneShadow.status, 0, output(firstCloneShadow))
  const secondCloneShadow = runHaxe(cloneShadowArgs)
  assert.strictEqual(secondCloneShadow.status, 0, output(secondCloneShadow))
  assert.strictEqual(firstCloneShadow.stdout, secondCloneShadow.stdout,
    'clone-shadowing contract output must be repeatable')
  assert.strictEqual(firstCloneShadow.stderr, secondCloneShadow.stderr,
    'clone-shadowing diagnostics must be repeatable')

	const borrowShadowArgs = [
		'-cp', 'src',
		'-cp', 'test/compiler',
		'--macro', 'RustBorrowScopeShadowingContract.run()',
		'--no-output'
	]
	const firstBorrowShadow = runHaxe(borrowShadowArgs)
	assert.strictEqual(firstBorrowShadow.status, 0, output(firstBorrowShadow))
	const secondBorrowShadow = runHaxe(borrowShadowArgs)
	assert.strictEqual(secondBorrowShadow.status, 0, output(secondBorrowShadow))
	assert.strictEqual(firstBorrowShadow.stdout, secondBorrowShadow.stdout,
		'borrow-scope shadowing contract output must be repeatable')
	assert.strictEqual(firstBorrowShadow.stderr, secondBorrowShadow.stderr,
		'borrow-scope shadowing diagnostics must be repeatable')

	const mutShadowArgs = [
		'-cp', 'src',
		'-cp', 'test/compiler',
		'--macro', 'RustMutInferenceShadowingContract.run()',
		'--no-output'
	]
	const firstMutShadow = runHaxe(mutShadowArgs)
	assert.strictEqual(firstMutShadow.status, 0, output(firstMutShadow))
	const secondMutShadow = runHaxe(mutShadowArgs)
	assert.strictEqual(secondMutShadow.status, 0, output(secondMutShadow))
	assert.strictEqual(firstMutShadow.stdout, secondMutShadow.stdout,
		'mut-inference shadowing contract output must be repeatable')
	assert.strictEqual(firstMutShadow.stderr, secondMutShadow.stderr,
		'mut-inference shadowing diagnostics must be repeatable')

	const cleanupShadowArgs = [
		'-cp', 'src',
		'-cp', 'test/compiler',
		'--macro', 'RustStatementCleanupShadowingContract.run()',
		'--no-output'
	]
	const firstCleanupShadow = runHaxe(cleanupShadowArgs)
	assert.strictEqual(firstCleanupShadow.status, 0, output(firstCleanupShadow))
	const secondCleanupShadow = runHaxe(cleanupShadowArgs)
	assert.strictEqual(secondCleanupShadow.status, 0, output(secondCleanupShadow))
	assert.strictEqual(firstCleanupShadow.stdout, secondCleanupShadow.stdout,
		'statement-cleanup shadowing contract output must be repeatable')
	assert.strictEqual(firstCleanupShadow.stderr, secondCleanupShadow.stderr,
		'statement-cleanup shadowing diagnostics must be repeatable')

  const expected = [
		'enum Choice {',
		'    First(i32),',
		'    Second(i32),',
		'}',
		'',
    'fn member_closure_contract(value: &dyn std::any::Any, iter: Vec<i32>) {',
    '    let _downcast = value.downcast_ref::<Option<String>>();',
    '    let _collected = iter.into_iter().collect::<Vec<_>>();',
    '    let typed = move |item: Option<String>| {',
    '        item',
    '    };',
    '    let _tupled = |(key, value): (i32, i32)| {',
    '        key + value',
    '    };',
		'    let _or_pattern = |(Choice::First(selected) | Choice::Second(selected)): Choice| {',
		'        selected',
		'    };',
		'    let _alias_or_pattern = |_whole @ (Choice::First(selected) | Choice::Second(selected)): Choice| {',
		'        selected',
		'    };',
		'    let _wildcard = |_: i32| {',
		'        0',
		'    };',
    '    typed(Option::None);',
    '}',
    ''
  ].join('\n')
  assert.strictEqual(first.stdout, expected)

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-structural-member-closures-'))
  try {
    const rustSourcePath = path.join(tempDir, 'contract.rs')
    fs.writeFileSync(rustSourcePath, `#![allow(dead_code)]\n${first.stdout}`)
    const rustc = cp.spawnSync('rustc', [
      '--crate-name', 'structural_member_closure_contract',
      '--crate-type', 'lib',
      '--edition', '2021',
      '-D', 'warnings',
      rustSourcePath,
      '-o', path.join(tempDir, 'libcontract.rlib')
    ], { cwd: repoRoot, encoding: 'utf8' })
    assert.strictEqual(rustc.status, 0, output(rustc))

    compileLegacyFixture(tempDir, 'field-member',
      'var expr:RustExpr = EField(EPath(RustPath.single("value")), "clone");', /RustMember/)
    compileLegacyFixture(tempDir, 'closure-parameters',
      'var expr:RustExpr = EClosure(["value"], {stmts: [], tail: null}, false);', /RustClosureParameter/)
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true })
  }

  const ast = fs.readFileSync(astPath, 'utf8')
  assert.doesNotMatch(ast, /\bEField\(recv:RustExpr,\s*field:String\)/,
    'field access must not retain a String member payload')
  assert.doesNotMatch(ast, /\bEClosure\(args:Array<String>/,
    'closure parameters must not retain rendered strings')

  const compiler = fs.readFileSync(compilerPath, 'utf8')
  assert.doesNotMatch(compiler, /EField\([^\n]*"[^"\n]*::</,
    'compiler lowering must not embed turbofish syntax in member strings')
  assert.doesNotMatch(compiler, /EClosure\([^\n]*\["[^"\n]*[:(),]/,
    'compiler lowering must not embed closure pattern/type syntax in strings')

  const ownershipPasses = [
    'BorrowScopeTighteningPass.hx',
    'CloneElisionPass.hx',
    'MutInferencePass.hx',
    'StatementCleanupPass.hx'
  ].map(name => fs.readFileSync(path.join(passDir, name), 'utf8')).join('\n')
  assert.match(ownershipPasses, /RustPathAnalysis\.matchesPlainMember\s*\(/,
    'ownership passes must match receiver operations structurally')
  assert.match(ownershipPasses, /RustPathAnalysis\.(?:patternBindsName|closureParametersBindName)\s*\(/,
    'ownership passes must honor structural closure and match-pattern shadowing')
  assert.doesNotMatch(ownershipPasses, /function\s+closureParametersBindName\s*\(/,
    'closure shadowing must have one shared structural authority')

  const noHxrtPass = fs.readFileSync(path.join(passDir, 'NoHxrtPass.hx'), 'utf8')
  assert.match(noHxrtPass, /RustPathAnalysis\.visitMemberTree\s*\(/,
    'no-hxrt analysis must inspect receiver-member generic arguments')
  assert.match(noHxrtPass, /RustPathAnalysis\.visitClosureParameterTree\s*\(/,
    'no-hxrt analysis must inspect closure parameter patterns and types')

  console.log('[rust-structural-member-closures-test] OK')
}

main()
