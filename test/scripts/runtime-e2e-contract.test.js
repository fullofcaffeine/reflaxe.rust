#!/usr/bin/env node

const assert = require('assert')
const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '..', '..')
const harnessPath = path.join(root, 'scripts', 'ci', 'harness.sh')
const verifierPath = path.join(root, 'scripts', 'ci', 'verify-required-rust-tests.sh')
const exampleDir = path.join(root, 'examples', 'profile_storyboard')
const requiredTestsPath = path.join(exampleDir, 'required-rust-tests.txt')
const weeklyPath = path.join(root, '.github', 'workflows', 'weekly-ci-evidence.yml')
const portableSysScript = path.join(root, 'scripts', 'ci', 'check-portable-sys-failures.py')
const lockReentrancyScript = path.join(root, 'scripts', 'ci', 'check-native-lock-reentrancy.py')
const lockReentrancyFixture = path.join(root, 'test', 'runtime_e2e', 'native_lock_reentrancy', 'Main.hx')
const pythonToolCommands = path.join(root, 'scripts', 'ci', 'python_tool_commands.py')
const windowsSmokePath = path.join(root, 'scripts', 'ci', 'windows-smoke.sh')

const requireMatch = (text, pattern, message) => {
  assert(pattern.test(text), message)
}

const main = () => {
  assert(fs.existsSync(requiredTestsPath), 'profile_storyboard must declare its required generated Rust tests')

  const requiredTests = fs.readFileSync(requiredTestsPath, 'utf8')
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(line => line.length > 0 && !line.startsWith('#'))

  assert(requiredTests.length >= 2, 'the profile runtime contract must require multiple meaningful tests')
  assert(new Set(requiredTests).size === requiredTests.length, 'required generated Rust test names must be unique')
  for (const testName of requiredTests) {
    assert(/^__hx_tests::[a-z0-9_]+$/.test(testName), `invalid generated Rust test name: ${testName}`)
  }

  for (const hxml of ['compile.portable.ci.hxml', 'compile.metal.ci.hxml']) {
    assert(fs.existsSync(path.join(exampleDir, hxml)), `profile runtime contract requires ${hxml}`)
  }

  const harness = fs.readFileSync(harnessPath, 'utf8')
  requireMatch(
    harness,
    /verify-required-rust-tests\.sh/,
    'the compiler harness must enforce required generated Rust test inventories'
  )
  assert(fs.existsSync(verifierPath), 'the generated Rust test inventory verifier must exist')

  assert(fs.existsSync(lockReentrancyScript), 'the native lock reentrancy subprocess harness must exist')
  assert(fs.existsSync(lockReentrancyFixture), 'the native lock reentrancy Haxe fixture must exist')
  assert(fs.existsSync(pythonToolCommands), 'Python E2E harnesses require a cross-platform project-tool launcher')
  requireMatch(
    harness,
    /test:native-lock-reentrancy/,
    'the full compiler harness must execute the native lock reentrancy contract'
  )
  const lockContract = fs.readFileSync(lockReentrancyScript, 'utf8')
  const portableSysContract = fs.readFileSync(portableSysScript, 'utf8')
  requireMatch(lockContract, /TIMEOUT_SECONDS\s*=\s*5/, 'native lock reentrancy cases require a hard process timeout')
  requireMatch(lockContract, /HXRT-LOCK-REENTRANCY/, 'native lock reentrancy must assert the stable runtime error identifier')
  requireMatch(
    lockContract,
    /project_haxe_command/,
    'native Windows Python must launch the project Haxe shim through the shared tool contract'
  )
  requireMatch(
    portableSysContract,
    /project_haxe_command/,
    'portable Sys Python must share the cross-platform project Haxe launcher'
  )
  const pythonTools = fs.readFileSync(pythonToolCommands, 'utf8')
  requireMatch(pythonTools, /haxeshim\.js/, 'the shared Python tool contract must own the Lix Haxe shim path')
  requireMatch(pythonTools, /\[node, str\(shim\)/, 'the Lix Haxe shim must be launched explicitly through Node')
  const windowsSmoke = fs.readFileSync(windowsSmokePath, 'utf8')
  requireMatch(
    windowsSmoke,
    /check-native-lock-reentrancy\.py/,
    'the curated Windows lane must execute the platform-independent native lock contract'
  )
  const verifier = fs.readFileSync(verifierPath, 'utf8')
  requireMatch(
    verifier,
    /cargo test.*--list/,
    'the compiler harness must inspect the generated Cargo test inventory before execution'
  )

  const weekly = fs.readFileSync(weeklyPath, 'utf8')
  requireMatch(
    weekly,
    /bash scripts\/ci\/local\.sh/,
    'weekly Linux evidence must execute the full compiler harness containing runtime E2E checks'
  )

  console.log(`runtime E2E contract: ok (${requiredTests.length} required tests)`)
}

main()
