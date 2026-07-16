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
const pathAnalysisPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'ast', 'RustPathAnalysis.hx')
const passDir = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'passes')
const harnessPath = path.join(repoRoot, 'scripts', 'ci', 'harness.sh')
const pathCompatFixture = path.join(repoRoot, 'test', 'positive', 'rust_impl_path_compat')

function runHaxe(args, cwd = repoRoot) {
  return cp.spawnSync(process.execPath, [haxeShim, ...args], {
    cwd,
    encoding: 'utf8'
  })
}

function output(result) {
  return `${result.stdout || ''}\n${result.stderr || ''}`
}

function main() {
  assert.match(
    fs.readFileSync(harnessPath, 'utf8'),
    /structural Rust trait and impl contract" npm run test:rust-structural-trait-impls/,
    'the full harness must run the structural trait/impl contract'
  )

  const args = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '-main', 'RustStructuralTraitImplContract',
    '--interp'
  ]
  const first = runHaxe(args)
  assert.strictEqual(first.status, 0, output(first))
  const second = runHaxe(args)
  assert.strictEqual(second.status, 0, output(second))
  assert.strictEqual(first.stdout, second.stdout, 'trait/impl printer bytes must be repeatable')
  assert.strictEqual(first.stderr, second.stderr, 'trait/impl diagnostics must be repeatable')

  const passArgs = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '--macro', 'RustStructuralTraitImplPassContract.run()',
    '--no-output'
  ]
  const firstPass = runHaxe(passArgs)
  assert.strictEqual(firstPass.status, 0, output(firstPass))
  const secondPass = runHaxe(passArgs)
  assert.strictEqual(secondPass.status, 0, output(secondPass))
  assert.strictEqual(firstPass.stdout, secondPass.stdout,
    'structural trait/impl pass output must be repeatable')
  assert.strictEqual(firstPass.stderr, secondPass.stderr,
    'structural trait/impl pass diagnostics must be repeatable')

  const noHxrtArgs = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '--macro', 'RustStructuralTraitImplPassContract.rejectNestedHxrt()',
    '--no-output'
  ]
  const firstNoHxrt = runHaxe(noHxrtArgs)
  assert.notStrictEqual(firstNoHxrt.status, 0,
    'rust_no_hxrt must reject runtime paths hidden inside trait and impl declarations')
  const secondNoHxrt = runHaxe(noHxrtArgs)
  assert.notStrictEqual(secondNoHxrt.status, 0,
    'repeat trait/impl no-hxrt contract must remain fail-closed')
  assert.strictEqual(firstNoHxrt.stdout, secondNoHxrt.stdout,
    'trait/impl no-hxrt output must be repeatable')
  assert.strictEqual(firstNoHxrt.stderr, secondNoHxrt.stderr,
    'trait/impl no-hxrt diagnostics must be repeatable')
  const noHxrtOutput = output(firstNoHxrt)
  assert.match(noHxrtOutput, /HXRS-NO-HXRT-EMITTED-RUNTIME/,
    'the rejection must come from emitted-runtime policy')
  assert.match(noHxrtOutput, /references `hxrt` 8 time\(s\)/,
    'no-hxrt traversal must observe all eight declaration and metadata-body paths')
  assert.match(noHxrtOutput, /raw item \[metadata-owned:trait-implementation\]/,
    'the admitted raw impl body must retain metadata authority inside structural headers')

  const expected = [
    '#![allow(dead_code)]',
    '',
    'struct Worker<T> {',
    '    value: T,',
    '}',
    '',
    "pub trait Processor<'a, T>: Send + Sync where T: Clone + 'a, 'a: 'static {",
    '    type Output: Clone;',
    "    type Lender<'item> where Self: 'item;",
    '    type Maybe: ?Sized;',
    '    const LIMIT: usize;',
    "    fn process<U: core::fmt::Debug>(&self, value: T, _other: U) -> Self::Output where U: Send;",
    '}',
    '',
    "impl<'a, T> Processor<'a, T> for Worker<T> where T: Clone + Send + Sync + 'a, 'a: 'static {",
    '    type Output = T;',
    "    type Lender<'item> = &'item T where Self: 'item;",
    '    type Maybe = str;',
    '    const LIMIT: usize = 4;',
    "    fn process<U: core::fmt::Debug>(&self, value: T, _other: U) -> Self::Output where U: Send {",
    '        value',
    '    }',
    '}',
    '',
    'impl<T> Worker<T> {',
    '    pub const DEFAULT_LIMIT: usize = 8;',
    '',
    '    fn take(self) -> () { }',
    '',
    '    fn reset(mut self) {',
    '        let _slot = &mut self.value;',
    '    }',
    '',
    "    fn borrow<'b>(&'b mut self) { }",
    '',
    '    fn borrow_mut(&mut self) { }',
    '',
    "    fn borrow_ref<'c>(&'c self) { }",
    '',
    '    fn boxed(self: Box<Self>) { }',
    '',
    '    fn boxed_mut(mut self: Box<Self>) {',
    '        let _boxed = &mut self;',
    '    }',
    '}',
    ''
  ].join('\n')
  assert.strictEqual(first.stdout, expected)

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-structural-trait-impl-'))
  try {
    const rustSourcePath = path.join(tempDir, 'contract.rs')
    fs.writeFileSync(rustSourcePath, first.stdout)
    const rustc = cp.spawnSync('rustc', [
      '--crate-name', 'structural_trait_impl_contract',
      '--crate-type', 'lib',
      '--edition', '2021',
      '-D', 'warnings',
      rustSourcePath,
      '-o', path.join(tempDir, 'libcontract.rlib')
    ], {cwd: tempDir, encoding: 'utf8'})
    assert.strictEqual(rustc.status, 0, output(rustc))

    const legacyDir = path.join(tempDir, 'legacy-impl')
    fs.mkdirSync(legacyDir)
    fs.writeFileSync(path.join(legacyDir, 'Main.hx'), `
import reflaxe.rust.ast.RustAST.RustGenericParameters;
import reflaxe.rust.ast.RustAST.RustImpl;
import reflaxe.rust.ast.RustAST.RustType;
class Main {
  static function main():Void {
    var legacy:RustImpl = {
      generics: RustGenericParameters.empty(),
      forType: RustType.RI32,
      functions: []
    };
  }
}
`)
    const legacy = runHaxe(['-cp', 'src', '-cp', legacyDir, '-main', 'Main', '--no-output'])
    assert.notStrictEqual(legacy.status, 0, 'legacy object-literal impls must be rejected')
    assert.match(output(legacy), /RustImpl|functions/,
      'legacy impl rejection must identify the removed declaration shape')

    const compatOut = path.join(tempDir, 'rust-impl-path-compat')
    const compat = runHaxe(['compile.hxml', '-D', `rust_output=${compatOut}`], pathCompatFixture)
    assert.strictEqual(compat.status, 0, output(compat))
    const targetSource = fs.readFileSync(path.join(compatOut, 'src', 'target.rs'), 'utf8')
    assert.match(targetSource, /impl crate::marker::Marker<-1> for Target \{ \}/,
      'marker-only rustImpl must accept trailing generic commas and negative const arguments')
    const compatBuild = cp.spawnSync('cargo', ['build', '--quiet'], {
      cwd: compatOut,
      encoding: 'utf8',
      env: {...process.env, RUSTFLAGS: '-D warnings'}
    })
    assert.strictEqual(compatBuild.status, 0, output(compatBuild))
  } finally {
    fs.rmSync(tempDir, {recursive: true, force: true})
  }

  const ast = fs.readFileSync(astPath, 'utf8')
  for (const shape of [
    'RTrait',
    'class RustImpl',
    'enum RustAssociatedItem',
    'class RustAssociatedFunction',
    'class RustWhereClause',
    'class RustWherePredicate'
  ]) {
    assert.match(ast, new RegExp(shape), `Rust AST must expose ${shape}`)
  }
  assert.doesNotMatch(ast, /typedef RustImpl\s*=\s*\{/,
    'impl declarations must no longer be open object literals')

  const compiler = fs.readFileSync(compilerPath, 'utf8')
  for (const rawReason of [
    'RawInterfaceTraitDeclaration',
    'RawClassTraitDeclaration',
    'RawClassTraitImplementation',
    'RawBaseTraitImplementation',
    'RawInterfaceTraitImplementation'
  ]) {
    assert.doesNotMatch(ast, new RegExp(`\\b${rawReason}\\b`),
      `${rawReason} must be removed from the Rust AST authority`)
    assert.doesNotMatch(compiler, new RegExp(`\\b${rawReason}\\b`),
      `${rawReason} must have no compiler producer after trait/impl migration`)
  }
  assert.doesNotMatch(compiler, /function emitClassTrait\([^)]*\):String/,
    'class trait lowering must return structural IR instead of rendered text')
  assert.doesNotMatch(compiler, /function renderRustImplBlock\s*\(/,
    'metadata impl headers must not be rendered by a compiler mini-printer')
  assert.match(compiler, /RustMetadataSyntax\.parsePath\s*\(/,
    'rustImpl trait paths must cross into structural IR at the metadata boundary')
  assert.match(compiler, /RustMetadataSyntax\.parseType\s*\(/,
    'rustImpl target overrides must cross into structural IR at the metadata boundary')

  const pathAnalysis = fs.readFileSync(pathAnalysisPath, 'utf8')
  assert.match(pathAnalysis, /function visitTraitTree\s*\(/,
    'trait declaration paths need one shared traversal authority')
  assert.match(pathAnalysis, /function visitImplTree\s*\(/,
    'impl declaration paths need one shared traversal authority')
  assert.match(pathAnalysis, /function visitWhereClause\s*\(/,
    'where-predicate paths need one shared traversal authority')

  for (const passName of [
    'BorrowScopeTighteningPass.hx',
    'CloneElisionPass.hx',
    'MutInferencePass.hx',
    'NormalizePass.hx',
    'StatementCleanupPass.hx'
  ]) {
    const source = fs.readFileSync(path.join(passDir, passName), 'utf8')
    assert.match(source, /case RTrait\s*\(/,
      `${passName} must recurse through structural trait default bodies`)
    assert.match(source, /case RImpl\s*\(/,
      `${passName} must recurse through structural impl bodies`)
  }

  for (const passName of [
    'BorrowScopeTighteningPass.hx',
    'CloneElisionPass.hx',
    'MutInferencePass.hx',
    'StatementCleanupPass.hx'
  ]) {
    const source = fs.readFileSync(path.join(passDir, passName), 'utf8')
    assert.match(source, /case AssocConst\s*\(declaration\)/,
      `${passName} must recurse through associated constant initializers`)
  }

  const noHxrt = fs.readFileSync(path.join(passDir, 'NoHxrtPass.hx'), 'utf8')
  assert.match(noHxrt, /RustPathAnalysis\.visitTraitTree\s*\(/,
    'no-hxrt policy must scan structural trait declarations')
  assert.match(noHxrt, /RustPathAnalysis\.visitImplTree\s*\(/,
    'no-hxrt policy must scan structural impl declarations')

  console.log('[rust-structural-trait-impls-test] OK')
}

main()
