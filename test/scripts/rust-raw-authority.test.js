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
    /typed raw-Rust authority contract" npm run test:rust-raw-authority/,
    'the compiler snapshot stage must run the typed raw-Rust authority contract after toolchain setup'
  )

  const positive = runHaxe([
    '-cp', 'src',
    '-cp', 'test/compiler',
    '-main', 'RustRawAuthorityContract',
    '--interp'
  ])
  assert.strictEqual(positive.status, 0, output(positive))

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-raw-authority-'))
  try {
    const directStringDir = path.join(root, 'direct-string')
    fs.mkdirSync(directStringDir, { recursive: true })
    fs.writeFileSync(path.join(directStringDir, 'Main.hx'), `
import reflaxe.rust.ast.RustAST.RustItem;
class Main {
  static function main():Void {
    var item:RustItem = RRaw("unclassified");
  }
}
`)
    const directString = runHaxe(['-cp', 'src', '-cp', directStringDir, '-main', 'Main', '--no-output'])
    assert.notStrictEqual(directString.status, 0, 'RRaw(String) must be rejected by the Haxe type checker')
    assert.match(output(directString), /RustRawCode/, 'direct raw-string rejection must name the required typed fragment')

    const privateConstructorDir = path.join(root, 'private-constructor')
    fs.mkdirSync(privateConstructorDir, { recursive: true })
    fs.writeFileSync(path.join(privateConstructorDir, 'Main.hx'), `
import reflaxe.rust.ast.RustAST.RustCompilerRawReason;
import reflaxe.rust.ast.RustAST.RustOrigin;
import reflaxe.rust.ast.RustAST.RustRawAuthority;
import reflaxe.rust.ast.RustAST.RustRawCode;
class Main {
  static function main():Void {
    var fragment = new RustRawCode("unclassified", RawCompilerOwned(RawStaticStorage), OriginCompilerGenerated);
  }
}
`)
    const privateConstructor = runHaxe(['-cp', 'src', '-cp', privateConstructorDir, '-main', 'Main', '--no-output'])
    assert.notStrictEqual(privateConstructor.status, 0, 'raw fragment construction must stay behind typed factories')
    assert.match(output(privateConstructor), /private/i, 'raw fragment constructor rejection must be explicit')
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }

  console.log('[rust-raw-authority-test] OK')
}

main()
