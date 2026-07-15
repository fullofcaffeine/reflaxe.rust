#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const haxeShim = path.join(repoRoot, 'node_modules', 'lix', 'bin', 'haxeshim.js')
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

function readPass(name) {
  return fs.readFileSync(path.join(passDir, name), 'utf8')
}

function main() {
  const args = [
    '-cp', 'src',
    '-cp', 'test/compiler',
    '-main', 'RustStructuralPathAnalysisContract',
    '--interp'
  ]
  const first = runHaxe(args)
  assert.strictEqual(first.status, 0, output(first))
  const second = runHaxe(args)
  assert.strictEqual(second.status, 0, output(second))
  assert.strictEqual(first.stdout, second.stdout, 'structural analysis output must be repeatable')
  assert.strictEqual(first.stderr, second.stderr, 'structural analysis diagnostics must be repeatable')
  assert.strictEqual(first.stdout, 'structural-path-analysis-ok\n')

  assert.match(
    fs.readFileSync(harnessPath, 'utf8'),
    /structural Rust pass analysis contract" npm run test:rust-structural-pass-analysis/,
    'the full harness must run the structural pass-analysis contract'
  )

  const ownershipPasses = [
    readPass('BorrowScopeTighteningPass.hx'),
    readPass('CloneElisionPass.hx'),
    readPass('MutInferencePass.hx'),
    readPass('StatementCleanupPass.hx')
  ].join('\n')
  assert.doesNotMatch(
    ownershipPasses,
    /\.plainRelativeIdentifierName\s*\(/,
    'ownership and cleanup passes must share the central structural local-identity predicate'
  )
  assert.match(ownershipPasses, /RustPathAnalysis\.localIdentifierName\s*\(/)
  assert.match(ownershipPasses, /RustPathAnalysis\.matchesPlainMember\s*\(/,
    'ownership passes must compare receiver members structurally')
  assert.match(ownershipPasses, /RustPathAnalysis\.closureParametersBindName\s*\(/,
    'ownership passes must share structural closure-shadowing analysis')

  const compiler = fs.readFileSync(path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustCompiler.hx'), 'utf8')
  assert.match(compiler, /RustPathAnalysis\.matchesPlainCrate\s*\(/,
    'compiler crate-target recognition must use the shared structural matcher')
  assert.doesNotMatch(compiler, /function\s+rustPathMatchesPlainCrate\s*\(/,
    'compiler lowering must not own a second crate-path matcher')

  const clonePass = readPass('CloneElisionPass.hx')
  assert.doesNotMatch(clonePass, /function\s+isDynamicFromPath\s*\(/,
    'clone elision must not own a second target-path matcher')
  assert.match(clonePass, /RustPathAnalysis\.matchesPlainRelative\s*\(/,
    'clone elision must compare the dynamic boxing target structurally')

  const noHxrtPass = readPass('NoHxrtPass.hx')
  assert.match(noHxrtPass, /RustPathAnalysis\.visitPathTree\s*\(/,
    'no-hxrt analysis must recursively traverse structural paths and their generic arguments')
  assert.match(noHxrtPass, /RustPathAnalysis\.visitTypeTree\s*\(/,
    'no-hxrt analysis must recursively traverse structural types')
  assert.match(noHxrtPass, /RustPathAnalysis\.visitPatternTree\s*\(/,
    'no-hxrt analysis must recursively traverse alias and compound patterns')
  assert.match(noHxrtPass, /RustPathAnalysis\.visitGenericParameters\s*\(/,
    'no-hxrt analysis must recursively traverse declaration generics')
  assert.match(noHxrtPass, /RustPathAnalysis\.visitMemberTree\s*\(/,
    'no-hxrt analysis must recursively traverse receiver-member generic arguments')
  assert.match(noHxrtPass, /RustPathAnalysis\.visitClosureParameterTree\s*\(/,
    'no-hxrt analysis must recursively traverse closure parameter patterns and types')
  assert.match(noHxrtPass, /RustPathAnalysis\.belongsToNamespace\s*\([^,]+,\s*"hxrt"\s*\)/,
    'no-hxrt analysis must use exact structural namespace ownership')
  assert.doesNotMatch(noHxrtPass, /firstIdentifierName\s*\(\)\s*==\s*"hxrt"/,
    'no-hxrt analysis must not maintain a second namespace predicate')

  console.log('[rust-structural-pass-analysis-test] OK')
}

main()
