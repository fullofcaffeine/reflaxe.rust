#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const haxeShim = path.join(repoRoot, 'node_modules', 'lix', 'bin', 'haxeshim.js')
const harnessPath = path.join(repoRoot, 'scripts', 'ci', 'harness.sh')
const policyPath = path.join(repoRoot, 'rust-raw-authority-policy.json')
const policyScriptPath = path.join(repoRoot, 'scripts', 'ci', 'rust-raw-authority-policy.js')
const inventoryPath = path.join(repoRoot, 'docs', 'rust-raw-authority-inventory.json')
const astPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'ast', 'RustAST.hx')
const compilerPath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustCompiler.hx')

function runHaxe(args) {
  return cp.spawnSync(process.execPath, [haxeShim, ...args], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
}

function output(result) {
  return `${result.stdout || ''}\n${result.stderr || ''}`
}

function runPolicy(root, mode) {
  return cp.spawnSync(process.execPath, [policyScriptPath, mode, '--root', root], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
}

function main() {
  assert(fs.existsSync(haxeShim), 'project-pinned Haxe shim must exist')
  assert(fs.existsSync(policyPath), 'the raw-authority policy must be checked in')
  assert(fs.existsSync(policyScriptPath), 'the raw-authority policy generator must be checked in')
  assert(fs.existsSync(inventoryPath), 'the generated raw-authority inventory must be checked in')
  assert.match(
    fs.readFileSync(harnessPath, 'utf8'),
    /typed raw-Rust authority contract" npm run test:rust-raw-authority/,
    'the compiler snapshot stage must run the typed raw-Rust authority contract after toolchain setup'
  )

  const policyCheck = runPolicy(repoRoot, '--check')
  assert.strictEqual(policyCheck.status, 0, output(policyCheck))

  const astSource = fs.readFileSync(astPath, 'utf8')
  const compilerSource = fs.readFileSync(compilerPath, 'utf8')
  assert.doesNotMatch(astSource, /\bRustCompilerRawReason\b|\bRawCompilerOwned\b|\bcompilerGenerated\s*\(|\bcompilerAt\s*\(/,
    'compiler-owned Rust strings must not remain constructible after typed-IR closure')
  assert.doesNotMatch(compilerSource, /RustRawCode\.(?:compilerGenerated|compilerAt)\s*\(/,
    'compiler lowering must not emit compiler-owned raw fragments')

  const positive = runHaxe([
    '-cp', 'src',
    '-cp', 'test/compiler',
    '--macro', 'RustRawAuthorityContract.run()',
    '--no-output'
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
import reflaxe.rust.ast.RustAST.RustRawCode;
class Main {
  static function main():Void {
    var fragment = new RustRawCode("unclassified", cast null, cast null);
  }
}
`)
    const privateConstructor = runHaxe(['-cp', 'src', '-cp', privateConstructorDir, '-main', 'Main', '--no-output'])
    assert.notStrictEqual(privateConstructor.status, 0, 'raw fragment construction must stay behind typed factories')
    assert.match(output(privateConstructor), /private/i, 'raw fragment constructor rejection must be explicit')

    const policyRoot = path.join(root, 'policy')
    fs.mkdirSync(policyRoot, {recursive: true})
    fs.copyFileSync(policyPath, path.join(policyRoot, 'rust-raw-authority-policy.json'))
    fs.cpSync(path.join(repoRoot, 'src'), path.join(policyRoot, 'src'), {recursive: true})
    fs.cpSync(path.join(repoRoot, 'std'), path.join(policyRoot, 'std'), {recursive: true})
    fs.cpSync(path.join(repoRoot, 'runtime'), path.join(policyRoot, 'runtime'), {recursive: true})
    fs.mkdirSync(path.join(policyRoot, 'docs'), {recursive: true})

    const firstWrite = runPolicy(policyRoot, '--write')
    assert.strictEqual(firstWrite.status, 0, output(firstWrite))
    const firstInventory = fs.readFileSync(path.join(policyRoot, 'docs', 'rust-raw-authority-inventory.json'), 'utf8')
    const firstAst = fs.readFileSync(path.join(policyRoot, 'src', 'reflaxe', 'rust', 'ast', 'RustAST.hx'), 'utf8')
    const secondWrite = runPolicy(policyRoot, '--write')
    assert.strictEqual(secondWrite.status, 0, output(secondWrite))
    assert.strictEqual(fs.readFileSync(path.join(policyRoot, 'docs', 'rust-raw-authority-inventory.json'), 'utf8'), firstInventory,
      'raw-authority inventory generation must be byte-for-byte deterministic')
    assert.strictEqual(fs.readFileSync(path.join(policyRoot, 'src', 'reflaxe', 'rust', 'ast', 'RustAST.hx'), 'utf8'), firstAst,
      'raw-authority Haxe generation must be byte-for-byte deterministic')

    const copiedCompilerPath = path.join(policyRoot, 'src', 'reflaxe', 'rust', 'RustCompiler.hx')
    fs.appendFileSync(copiedCompilerPath, '\nRustRawCode.targetCodeInjectionAt("unreviewed", cast null);\n')
    const unreviewedGrowth = runPolicy(policyRoot, '--check')
    assert.notStrictEqual(unreviewedGrowth.status, 0, 'an unreviewed raw call site must make the inventory fail closed')
    assert.match(output(unreviewedGrowth), /inventory|call site|stale/i,
      'raw-site growth failure must explain that reviewed inventory evidence is stale')

    fs.appendFileSync(copiedCompilerPath, '\nRustRawCode.compilerAt("forbidden", cast null, cast null);\n')
    const compilerRaw = runPolicy(policyRoot, '--check')
    assert.notStrictEqual(compilerRaw.status, 0, 'a compiler-owned raw factory must fail the closure guard')
    assert.match(output(compilerRaw), /compilerAt|unsupported raw factory|compiler-owned/i,
      'compiler-owned raw rejection must name the forbidden authority')
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }

  console.log('[rust-raw-authority-test] OK')
}

main()
