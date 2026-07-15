#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const haxeShim = path.join(repoRoot, 'node_modules', 'lix', 'bin', 'haxeshim.js')
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
  assert(fs.existsSync(haxeShim), 'project-pinned Haxe shim must exist')
  assert.match(
    fs.readFileSync(harnessPath, 'utf8'),
    /structural Rust path IR contract" npm run test:rust-structural-path-ir/,
    'the compiler snapshot stage must run the structural path IR contract after toolchain setup'
  )

  const args = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '-main', 'RustStructuralPathContract',
    '--interp'
  ]
  const first = runHaxe(args)
  assert.strictEqual(first.status, 0, output(first))
  const second = runHaxe(args)
  assert.strictEqual(second.status, 0, output(second))
  assert.strictEqual(first.stdout, second.stdout, 'structural printer bytes must be repeatable')
  assert.strictEqual(first.stderr, second.stderr, 'structural printer diagnostics must be repeatable')
  assert.strictEqual(first.stdout, [
    'Option<Vec<T>>',
    "&'a T",
    '[T; N]',
    "Buffer<'a, T, 32>",
    'hxrt::array::Array::<T, 32>::new',
    '<T as core::iter::Iterator>::Item',
    "<'a: 'static, T: Clone + Send + 'a, const N: usize = 32>",
    ''
  ].join('\n'))

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-structural-path-'))
  try {
    const rendered = first.stdout.trimEnd().split('\n')
    const rustSource = `
#![allow(dead_code)]

mod hxrt {
    pub mod array {
        pub struct Array<T, const N: usize>(pub [T; N]);

        impl<T: Default, const N: usize> Array<T, N> {
            pub fn new() -> Self {
                Self(std::array::from_fn(|_| T::default()))
            }
        }
    }
}

struct Buffer<'a, T, const N: usize>(&'a T, [T; N]);
type Nested<T> = ${rendered[0]};
type Borrowed<'a, T> = ${rendered[1]};
type Fixed<T, const N: usize> = ${rendered[2]};
type Buffered<'a, T> = ${rendered[3]};
fn build<T: Default>() { let _ = ${rendered[4]}; }
fn qualified<T: core::iter::Iterator>() -> ${rendered[5]} { loop {} }
struct Declaration${rendered[6]}(&'a T, [u8; N]);
`
    const rustSourcePath = path.join(root, 'contract.rs')
    const rustOutputPath = path.join(root, 'libcontract.rlib')
    fs.writeFileSync(rustSourcePath, rustSource)
    const rustc = cp.spawnSync('rustc', [
      '--crate-name', 'structural_path_contract',
      '--crate-type', 'lib',
      '--edition', '2021',
      '-D', 'warnings',
      rustSourcePath,
      '-o', rustOutputPath
    ], { cwd: repoRoot, encoding: 'utf8' })
    assert.strictEqual(rustc.status, 0, output(rustc))

    const directStringDir = path.join(root, 'direct-string')
    fs.mkdirSync(directStringDir, { recursive: true })
    fs.writeFileSync(path.join(directStringDir, 'Main.hx'), `
import reflaxe.rust.ast.RustAST.RustPath;
import reflaxe.rust.ast.RustASTPrinter;
class Main {
  static function main():Void {
    RustASTPrinter.printTypePath("std::vec::Vec");
  }
}
`)
    const directString = runHaxe(['-cp', 'src', '-cp', directStringDir, '-main', 'Main', '--no-output'])
    assert.notStrictEqual(directString.status, 0, 'whole-path String payloads must be rejected by the Haxe type checker')
    assert.match(output(directString), /RustPath/, 'whole-path rejection must name the required structural path')

    const genericStringDir = path.join(root, 'generic-string')
    fs.mkdirSync(genericStringDir, { recursive: true })
    fs.writeFileSync(path.join(genericStringDir, 'Main.hx'), `
import reflaxe.rust.ast.RustAST.RustGenericArgument;
class Main {
  static function main():Void {
    var argument:RustGenericArgument = GenericType("Vec<T>");
  }
}
`)
    const genericString = runHaxe(['-cp', 'src', '-cp', genericStringDir, '-main', 'Main', '--no-output'])
    assert.notStrictEqual(genericString.status, 0, 'generic type String payloads must be rejected by the Haxe type checker')
    assert.match(output(genericString), /RustType/, 'generic type rejection must name the required typed Rust type')

    const privateConstructorDir = path.join(root, 'private-constructor')
    fs.mkdirSync(privateConstructorDir, { recursive: true })
    fs.writeFileSync(path.join(privateConstructorDir, 'Main.hx'), `
import reflaxe.rust.ast.RustAST.RustIdentifier;
class Main {
  static function main():Void {
    var identifier = new RustIdentifier("unchecked", false);
  }
}
`)
    const privateConstructor = runHaxe(['-cp', 'src', '-cp', privateConstructorDir, '-main', 'Main', '--no-output'])
    assert.notStrictEqual(privateConstructor.status, 0, 'identifier construction must stay behind validating factories')
    assert.match(output(privateConstructor), /private/i, 'identifier constructor rejection must be explicit')
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }

  console.log('[rust-structural-path-ir-test] OK')
}

main()
