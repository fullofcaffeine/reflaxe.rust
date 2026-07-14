#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const checker = path.join(repoRoot, 'scripts', 'ci', 'diagnostic-contract-check.js')
const manifestPath = path.join(repoRoot, 'docs', 'diagnostic-contract.json')

function run(args = []) {
  return cp.spawnSync(process.execPath, [checker, ...args], { cwd: repoRoot, encoding: 'utf8' })
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`)
}

function expectFailure(result, pattern) {
  assert.notStrictEqual(result.status, 0, 'diagnostic contract guard unexpectedly succeeded')
  assert.match(`${result.stdout}\n${result.stderr}`, pattern)
}

function main() {
  assert(fs.existsSync(checker), 'diagnostic contract guard must exist')
  assert(fs.existsSync(manifestPath), 'diagnostic contract manifest must exist')
  const baseline = run()
  assert.strictEqual(baseline.status, 0, baseline.stderr || baseline.stdout)

  const canonical = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  const families = new Set(canonical.diagnostics.map((entry) => entry.family))
  for (const family of ['profile', 'async', 'no-hxrt', 'borrow', 'send-sync', 'native-import', 'metadata', 'cargo', 'dynamic', 'reflection']) {
    assert(families.has(family), `missing admitted diagnostic family ${family}`)
  }

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-diagnostic-contract-'))
  try {
    const removed = structuredClone(canonical)
    const removedEntry = removed.diagnostics.shift()
    const removedPath = path.join(root, 'removed.json')
    writeJson(removedPath, removed)
    expectFailure(run(['--manifest', removedPath, '--skip-doc']), new RegExp(`missing compiler diagnostic.*${removedEntry.id}`))

    const invalidSeverity = structuredClone(canonical)
    invalidSeverity.diagnostics[0].severity = 'sometimes-error'
    const invalidSeverityPath = path.join(root, 'invalid-severity.json')
    writeJson(invalidSeverityPath, invalidSeverity)
    expectFailure(run(['--manifest', invalidSeverityPath, '--skip-doc']), /invalid severity/)

    const duplicate = structuredClone(canonical)
    duplicate.diagnostics.push(structuredClone(duplicate.diagnostics[0]))
    const duplicatePath = path.join(root, 'duplicate.json')
    writeJson(duplicatePath, duplicate)
    expectFailure(run(['--manifest', duplicatePath, '--skip-doc']), /duplicate diagnostic id/)

    const stableIntroducedVersion = structuredClone(canonical)
    stableIntroducedVersion.diagnostics[0].introduced = '1.0.0'
    const stableIntroducedVersionPath = path.join(root, 'stable-introduced-version.json')
    writeJson(stableIntroducedVersionPath, stableIntroducedVersion)
    const stableIntroducedVersionResult = run(['--manifest', stableIntroducedVersionPath, '--skip-doc'])
    assert.strictEqual(stableIntroducedVersionResult.status, 0, stableIntroducedVersionResult.stderr || stableIntroducedVersionResult.stdout)

    const unknownReplacement = structuredClone(canonical)
    unknownReplacement.diagnostics[0].status = 'deprecated'
    unknownReplacement.diagnostics[0].replacement = 'HXRS-NOT-REGISTERED'
    const unknownReplacementPath = path.join(root, 'unknown-replacement.json')
    writeJson(unknownReplacementPath, unknownReplacement)
    expectFailure(run(['--manifest', unknownReplacementPath, '--skip-doc']), /replacement is not registered/)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }

  console.log('[diagnostic-contract-test] OK')
}

main()
