#!/usr/bin/env node

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { spawnSync } = require('child_process')

const repoRoot = path.resolve(__dirname, '..', '..')
const checker = path.join(repoRoot, 'scripts', 'ci', 'testing-surface-scorecards.js')
const manifestPath = path.join(repoRoot, 'docs', 'testing-surface-scorecards.json')

function run(args) {
  return spawnSync(process.execPath, [checker, ...args], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
}

function output(result) {
  return `${result.stdout || ''}${result.stderr || ''}`
}

function mutate(mutator) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-testing-scorecards-'))
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  mutator(manifest)
  const file = path.join(root, 'manifest.json')
  fs.writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`)
  return { root, file }
}

function expectFailure(mutator, pattern) {
  const fixture = mutate(mutator)
  try {
    const result = run(['--check', '--manifest', fixture.file, '--skip-generated-doc'])
    assert.notStrictEqual(result.status, 0, output(result))
    assert.match(output(result), pattern)
  } finally {
    fs.rmSync(fixture.root, { recursive: true, force: true })
  }
}

const clean = run(['--check'])
assert.strictEqual(clean.status, 0, output(clean))

expectFailure((manifest) => {
  manifest.surfaces = manifest.surfaces.filter((surface) => surface.id !== 'runtime')
}, /missing required product surface: runtime/)

expectFailure((manifest) => {
  const metal = manifest.surfaces.find((surface) => surface.id === 'representation-metal')
  metal.officialHaxeTargetQualification = 'applies'
}, /official Haxe target qualification applies only to portable-compiler/)

expectFailure((manifest) => {
  const flagship = manifest.examples.find((example) => example.tier === 'flagship-application')
  flagship.observedLevels = ['source-snapshot']
}, /flagship application must execute compile, cargo-build, and runtime/)

expectFailure((manifest) => {
  const runtimeExample = manifest.examples.find((example) => example.surfaces.includes('runtime'))
  runtimeExample.observedLevels = runtimeExample.observedLevels.filter((level) => level !== 'runtime')
}, /cannot support runtime without observed level: runtime/)

expectFailure((manifest) => {
  manifest.examples.pop()
}, /example classification does not match examples\/ directories/)

expectFailure((manifest) => {
  manifest.representativeWorkflow.expectedResult.source = 'implementation-under-test'
}, /expected result source must be independent of the implementation under test/)

console.log('[testing-surface-scorecards] contract mutations passed')
