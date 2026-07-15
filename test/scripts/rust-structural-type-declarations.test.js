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

function runHaxe(args) {
  return cp.spawnSync(process.execPath, [haxeShim, ...args], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
}

function output(result) {
  return `${result.stdout || ''}\n${result.stderr || ''}`
}

function main() {
  assert.match(
    fs.readFileSync(harnessPath, 'utf8'),
    /structural Rust type declaration contract" npm run test:rust-structural-type-declarations/,
    'the compiler snapshot stage must run the structural type/declaration contract'
  )

  const args = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '-main', 'RustStructuralTypeDeclarationContract',
    '--interp'
  ]
  const first = runHaxe(args)
  assert.strictEqual(first.status, 0, output(first))
  const second = runHaxe(args)
  assert.strictEqual(second.status, 0, output(second))
  assert.strictEqual(first.stdout, second.stdout, 'declaration printer bytes must be repeatable')
  assert.strictEqual(first.stderr, second.stderr, 'declaration diagnostics must be repeatable')

  const expected = [
    "struct Holder<'a, T: Clone + Send + 'a, const N: usize> {",
    "    value: &'a mut [T; N],",
    '}',
    '',
    'enum Message<T> {',
    '    Value(Option<T>),',
    '}',
    '',
    "impl<'a, T: Clone + Send + 'a, const N: usize> Holder<'a, T, N> {",
    '    fn call<U: core::fmt::Debug>(_operation: &str, _callback: crate::HxRc<dyn Fn(U) -> T + Send + Sync + \'a>) -> Option<T> {',
    '        None',
    '    }',
    '}',
    ''
  ].join('\n')
  assert.strictEqual(first.stdout, expected)

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-structural-declarations-'))
  try {
    const rustSourcePath = path.join(tempDir, 'contract.rs')
    fs.writeFileSync(rustSourcePath, `#![allow(dead_code)]\ntype HxRc<T> = std::sync::Arc<T>;\n\n${first.stdout}`)
    const rustc = cp.spawnSync('rustc', [
      '--crate-name', 'structural_type_declaration_contract',
      '--crate-type', 'lib',
      '--edition', '2021',
      '-D', 'warnings',
      rustSourcePath,
      '-o', path.join(tempDir, 'libcontract.rlib')
    ], { cwd: repoRoot, encoding: 'utf8' })
    assert.strictEqual(rustc.status, 0, output(rustc))

    const legacyDir = path.join(tempDir, 'legacy-type')
    fs.mkdirSync(legacyDir)
    fs.writeFileSync(path.join(legacyDir, 'Main.hx'), `
import reflaxe.rust.ast.RustAST.RustType;
class Main {
  static function main():Void {
    var type:RustType = RPath("Option<T>");
  }
}
`)
    const legacy = runHaxe(['-cp', 'src', '-cp', legacyDir, '-main', 'Main', '--no-output'])
    assert.notStrictEqual(legacy.status, 0, 'legacy string-backed Rust types must be rejected')
    assert.match(output(legacy), /RPath/, 'legacy constructor rejection must identify RPath')
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true })
  }

  const ast = fs.readFileSync(astPath, 'utf8')
  const compiler = fs.readFileSync(compilerPath, 'utf8')
  assert.doesNotMatch(ast, /\bRPath\(path:String\)/, 'RustType must not retain a string-backed path variant')
  assert.doesNotMatch(ast, /\bRRef\(inner:RustType/, 'RustType must not retain the legacy reference variant')
  assert.doesNotMatch(ast, /generics:Array<String>/, 'declaration generics must use RustGenericParameters')
  assert.doesNotMatch(ast, /var forType:String/, 'impl targets must use structural RustType')
  assert.doesNotMatch(compiler, /\bRPath\(/, 'compiler type producers must not construct legacy string paths')
  assert.doesNotMatch(compiler, /\bRRef\(/, 'compiler type producers must not construct legacy references')

  console.log('[rust-structural-type-declarations-test] OK')
}

main()
