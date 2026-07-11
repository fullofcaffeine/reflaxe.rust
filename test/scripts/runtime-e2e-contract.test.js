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
