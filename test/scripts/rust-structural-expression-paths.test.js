#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const haxeShim = path.join(repoRoot, 'node_modules', 'lix', 'bin', 'haxeshim.js')
const astPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'ast', 'RustAST.hx')
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

function compileLegacyFixture(root, name, expression, expectedType) {
  const fixtureDir = path.join(root, name)
  fs.mkdirSync(fixtureDir, { recursive: true })
  fs.writeFileSync(path.join(fixtureDir, 'Main.hx'), `
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustPattern;
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
    /structural Rust expression path contract" npm run test:rust-structural-expression-paths/,
    'the full harness must run the structural expression/path contract'
  )

  const args = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '-main', 'RustStructuralExpressionPathContract',
    '--interp'
  ]
  const first = runHaxe(args)
  assert.strictEqual(first.status, 0, output(first))
  const second = runHaxe(args)
  assert.strictEqual(second.status, 0, output(second))
  assert.strictEqual(first.stdout, second.stdout, 'expression/path printer bytes must be repeatable')
  assert.strictEqual(first.stderr, second.stderr, 'expression/path diagnostics must be repeatable')

  const expected = [
    "fn build<'a, U, const N: usize, T: Factory<'a, U, N>>(value: Option<U>) -> Packet<U, N> {",
    '    let index: usize = 0 as usize;',
    '    let selected = match value {',
    '        Option::Some(inner) => inner,',
    '        Option::None => unreachable!(),',
    '    };',
    "    Packet::<U, N> { value: <T as Factory<'a, U, N>>::make::<U>(selected), index: index }",
    '}',
    ''
  ].join('\n')
  assert.strictEqual(first.stdout, expected)

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-structural-expression-paths-'))
  try {
    const rustSourcePath = path.join(tempDir, 'contract.rs')
    fs.writeFileSync(rustSourcePath, `#![allow(dead_code)]
trait Factory<'a, U, const N: usize> {
    fn make<V>(value: U) -> U;
}
struct Packet<U, const N: usize> {
    value: U,
    index: usize,
}

${first.stdout}`)
    const rustc = cp.spawnSync('rustc', [
      '--crate-name', 'structural_expression_path_contract',
      '--crate-type', 'lib',
      '--edition', '2021',
      '-D', 'warnings',
      rustSourcePath,
      '-o', path.join(tempDir, 'libcontract.rlib')
    ], { cwd: repoRoot, encoding: 'utf8' })
    assert.strictEqual(rustc.status, 0, output(rustc))

    compileLegacyFixture(tempDir, 'expression-path',
      'var expr:RustExpr = EPath("Option::None");', /RustPath/)
    compileLegacyFixture(tempDir, 'pattern-path',
      'var pattern:RustPattern = PPath("Option::None");', /RustPath/)
    compileLegacyFixture(tempDir, 'tuple-struct-pattern',
      'var pattern:RustPattern = PTupleStruct("Option::Some", []);', /RustPath/)
    compileLegacyFixture(tempDir, 'cast-target',
      'var expr:RustExpr = ECast(ELitInt(0), "usize");', /RustType/)
    compileLegacyFixture(tempDir, 'struct-literal-path',
      'var expr:RustExpr = EStructLit("Packet", []);', /RustPath/)
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true })
  }

  const ast = fs.readFileSync(astPath, 'utf8')
  assert.doesNotMatch(ast, /\bEPath\(path:String\)/, 'expression paths must not retain String payloads')
  assert.doesNotMatch(ast, /\bPPath\(path:String\)/, 'pattern paths must not retain String payloads')
  assert.doesNotMatch(ast, /\bPTupleStruct\(path:String/, 'tuple-struct patterns must not retain String payloads')
  assert.doesNotMatch(ast, /\bECast\(expr:RustExpr, ty:String\)/, 'cast targets must use RustType')
  assert.doesNotMatch(ast, /\bEStructLit\(path:String/, 'struct-literal paths must not retain String payloads')

  console.log('[rust-structural-expression-paths-test] OK')
}

main()
