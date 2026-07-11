#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const checker = path.join(repoRoot, 'scripts', 'ci', 'public-compatibility-manifest-check.js')
const sourceManifest = path.join(repoRoot, 'docs', 'public-compatibility-manifest.json')

function run(args) {
  return cp.spawnSync(process.execPath, [checker, ...args], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`)
}

function expectFailure(result, pattern) {
  assert.notStrictEqual(result.status, 0, 'guard unexpectedly succeeded')
  assert.match(`${result.stdout}\n${result.stderr}`, pattern)
}

function main() {
  assert(fs.existsSync(checker), 'public compatibility guard must exist')
  assert(fs.existsSync(sourceManifest), 'public compatibility manifest must exist')

  const baseline = run([])
  assert.strictEqual(baseline.status, 0, baseline.stderr || baseline.stdout)

  const canonical = JSON.parse(fs.readFileSync(sourceManifest, 'utf8'))
  const hxRef = canonical.haxeTypes.find((entry) => entry.name === 'rust.HxRef')
  assert.strictEqual(hxRef.contract, 'rust-hxref', 'rust.HxRef must use the explicit opaque-handle contract')
  const hxRefContract = canonical.contracts.find((entry) => entry.id === hxRef.contract)
  assert.strictEqual(hxRefContract.class, 'qualified-stable-candidate')
  assert(hxRefContract.exclusions.some((value) => value.includes('Arc/HxCell')), 'HxRef representation must remain non-contractual')

  const rustMetal = canonical.metadata.find((entry) => entry.name === 'rustMetal')
  assert.strictEqual(rustMetal.contract, 'metadata-stable', '@:rustMetal must be the canonical stable metal-island metadata')
  const haxeMetal = canonical.metadata.find((entry) => entry.name === 'haxeMetal')
  assert.strictEqual(haxeMetal.contract, 'haxe-metal-alias', '@:haxeMetal must remain a compatibility alias')
  const haxeMetalAlias = canonical.contracts.find((entry) => entry.id === haxeMetal.contract)
  assert.strictEqual(haxeMetalAlias.class, 'stable-candidate')
  assert.strictEqual(haxeMetalAlias.status, 'deprecated')
  assert(haxeMetalAlias.qualification.includes('rustMetal'), 'the alias contract must name @:rustMetal as the replacement')

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-public-compat-'))
  try {
    const manifest = canonical

    const invalidClass = structuredClone(manifest)
    invalidClass.contracts[0].class = 'stable candidate for documented operations'
    const invalidClassPath = path.join(root, 'invalid-class.json')
    writeJson(invalidClassPath, invalidClass)
    expectFailure(run(['--manifest', invalidClassPath, '--skip-doc']), /noncanonical compatibility class/)

    const missingType = structuredClone(manifest)
    const removed = missingType.haxeTypes.shift()
    const missingTypePath = path.join(root, 'missing-type.json')
    writeJson(missingTypePath, missingType)
    expectFailure(run(['--manifest', missingTypePath, '--skip-doc']), new RegExp(`unclassified Haxe type.*${removed.name.replaceAll('.', '\\.')}`, 's'))

    const duplicateType = structuredClone(manifest)
    duplicateType.haxeTypes.push(structuredClone(duplicateType.haxeTypes[0]))
    const duplicateTypePath = path.join(root, 'duplicate-type.json')
    writeJson(duplicateTypePath, duplicateType)
    expectFailure(run(['--manifest', duplicateTypePath, '--skip-doc']), /duplicate Haxe type/)

    const first = run(['--render'])
    const second = run(['--render'])
    assert.strictEqual(first.status, 0, first.stderr)
    assert.strictEqual(second.status, 0, second.stderr)
    assert.strictEqual(first.stdout, second.stdout, 'generated compatibility summary must be byte-for-byte repeatable')
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }

  console.log('[public-compatibility-manifest-test] OK')
}

main()
