#!/usr/bin/env node

const assert = require('assert')
const { execFileSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { assertPackageInputsTracked } = require('../../scripts/release/package-input-cleanliness.js')

function git(cwd, args) {
  return execFileSync('git', args, { cwd, encoding: 'utf8' })
}

function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-package-input-cleanliness-'))
  try {
    git(temp, ['init', '-q'])
    fs.mkdirSync(path.join(temp, 'src'), { recursive: true })
    fs.writeFileSync(path.join(temp, 'src', 'Tracked.hx'), 'class Tracked {}\n')
    fs.writeFileSync(
      path.join(temp, '.gitignore'),
      'vendor/haxe/\n*.n\ndocs/stdlib-provenance-ledger.json\n'
    )
    git(temp, ['add', '.'])
    git(temp, [
      '-c',
      'user.name=Package Test',
      '-c',
      'user.email=package@example.invalid',
      'commit',
      '-q',
      '-m',
      'fixture'
    ])
    assert.doesNotThrow(() => assertPackageInputsTracked(temp))

    fs.writeFileSync(path.join(temp, 'local-notes.txt'), 'outside package roots\n')
    assert.doesNotThrow(() => assertPackageInputsTracked(temp))

    fs.mkdirSync(path.join(temp, 'runtime'), { recursive: true })
    fs.writeFileSync(path.join(temp, 'runtime', 'payload.rs'), 'untracked\n')
    assert.throws(() => assertPackageInputsTracked(temp), /runtime\/payload\.rs/)
    fs.rmSync(path.join(temp, 'runtime'), { recursive: true })

    fs.mkdirSync(path.join(temp, 'vendor', 'haxe'), { recursive: true })
    fs.writeFileSync(path.join(temp, 'vendor', 'haxe', 'payload.hx'), 'ignored but packaged\n')
    assert.throws(() => assertPackageInputsTracked(temp), /vendor\/haxe\/payload\.hx/)
    fs.rmSync(path.join(temp, 'vendor'), { recursive: true })

    fs.writeFileSync(path.join(temp, 'run.n'), 'ignored executable input\n')
    assert.throws(() => assertPackageInputsTracked(temp), /run\.n/)
    fs.rmSync(path.join(temp, 'run.n'))

    fs.writeFileSync(path.join(temp, 'Run.hx'), 'untracked source input\n')
    assert.throws(() => assertPackageInputsTracked(temp), /Run\.hx/)
    fs.rmSync(path.join(temp, 'Run.hx'))

    fs.mkdirSync(path.join(temp, 'docs'), { recursive: true })
    fs.writeFileSync(
      path.join(temp, 'docs', 'stdlib-provenance-ledger.json'),
      '{"unreviewed":true}\n'
    )
    assert.throws(
      () => assertPackageInputsTracked(temp),
      /docs\/stdlib-provenance-ledger\.json/
    )
    fs.rmSync(path.join(temp, 'docs', 'stdlib-provenance-ledger.json'))

    const external = path.join(temp, '..', `external-${path.basename(temp)}.json`)
    fs.writeFileSync(external, '{"external":true}\n')
    fs.symlinkSync(external, path.join(temp, 'docs', 'stdlib-provenance-ledger.json'))
    git(temp, ['add', '-f', 'docs/stdlib-provenance-ledger.json'])
    git(temp, [
      '-c',
      'user.name=Package Test',
      '-c',
      'user.email=package@example.invalid',
      'commit',
      '-q',
      '-m',
      'tracked symlink'
    ])
    assert.strictEqual(git(temp, ['status', '--porcelain', '--untracked-files=no']), '')
    assert.throws(
      () => assertPackageInputsTracked(temp),
      /release package input must be a regular Git blob: docs\/stdlib-provenance-ledger\.json/
    )
    fs.rmSync(external)

    console.log('[package-input-cleanliness-test] OK')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

main()
