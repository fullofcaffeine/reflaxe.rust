#!/usr/bin/env node

const assert = require('node:assert/strict')
const crypto = require('node:crypto')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const test = require('node:test')

const repoRoot = path.resolve(__dirname, '..', '..')
const fixtureRoot = path.join(repoRoot, 'test', 'contract', 'support_crate_admission_runner')
const haxe = process.env.HAXE_BIN || path.join(repoRoot, 'node_modules', '.bin', 'haxe')

function runProbe(script, expected, deadline = 2000, extraDefines = []) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-runner-'))
  const executable = path.join(root, 'probe')
  try {
    fs.writeFileSync(executable, `#!/bin/sh\n${script}\n`, { mode: 0o700 })
    const result = spawnSync(haxe, [
      'compile.hxml',
      '-D', `support_crate_runner_executable=${executable}`,
      '-D', `support_crate_runner_expected=${expected}`,
      '-D', `support_crate_runner_deadline_ms=${deadline}`,
      ...extraDefines.flatMap(value => ['-D', value])
    ], {
      cwd: fixtureRoot,
      encoding: 'utf8',
      env: process.env,
      timeout: 10000
    })
    assert.ifError(result.error)
    assert.equal(result.status, 0, `${result.stdout || ''}${result.stderr || ''}`)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

function runHelperValidation({ mode = 0o700, expectedSha256, symlink = false }, expected) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-helper-validation-'))
  const target = path.join(root, 'target')
  const executable = symlink ? path.join(root, 'probe') : target
  try {
    const bytes = Buffer.from("#!/bin/sh\nprintf 'x'\n")
    fs.writeFileSync(target, bytes, { mode })
    fs.chmodSync(target, mode)
    if (symlink) fs.symlinkSync(target, executable)
    const digest = expectedSha256 || crypto.createHash('sha256').update(bytes).digest('hex')
    const result = spawnSync(haxe, [
      'compile.hxml',
      '-D', `support_crate_runner_executable=${executable}`,
      '-D', `support_crate_runner_expected=${expected}`,
      '-D', `support_crate_runner_sha256=${digest}`
    ], {
      cwd: fixtureRoot,
      encoding: 'utf8',
      env: process.env
    })
    assert.ifError(result.error)
    assert.equal(result.status, 0, `${result.stdout || ''}${result.stderr || ''}`)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

test('the runner retains exact stdout only after a clean exit', () => {
  runProbe("printf 'x'", 'Completed')
})

test('the runner rejects a nonzero helper exit', () => {
  runProbe('exit 7', 'ExitFailed')
})

test('the runner rejects output from a helper terminated by a signal', () => {
  runProbe("printf 'x'; kill -TERM $$", 'ExitFailed')
  runProbe("printf 'x'; kill -KILL $$", 'ExitFailed')
})

test('the runner rejects any helper stderr', () => {
  runProbe("printf 'problem' >&2", 'StderrRejected')
})

test('the runner kills a helper at its deadline and discards partial stdout', () => {
  runProbe("printf 'x'; exec /bin/sleep 10", 'TimedOut', 100)
})

test('the deadline remains active until inherited output pipes reach EOF', () => {
  runProbe("/bin/sleep 10 & printf 'x'; exit 0", 'TimedOut', 100)
})

test('an exception after spawn closes the process, pipes, timer, and loop', () => {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    runProbe('exec /bin/sleep 10', 'PipeFailed', 2000, ['support_crate_admission_test_throw_after_spawn'])
  }
})

test('stdout above the fixed response limit is rejected', () => {
  runProbe('dd if=/dev/zero bs=1048576 count=41 2>/dev/null', 'ProtocolRejected')
})

test('helper admission requires an exact digest and owner-executable mode', () => {
  runHelperValidation({}, 'HelperValid')
  runHelperValidation({ expectedSha256: '0'.repeat(64) }, 'HelperInvalid')
  runHelperValidation({ mode: 0o770 }, 'HelperInvalid')
})

test('helper admission rejects a symbolic-link executable path', () => {
  runHelperValidation({ symlink: true }, 'HelperInvalid')
})
