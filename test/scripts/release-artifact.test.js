#!/usr/bin/env node

const assert = require('assert')
const crypto = require('crypto')
const { execFileSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { strToU8, zipSync } = require('fflate')

const repoRoot = path.resolve(__dirname, '..', '..')
const zipModulePath = path.join(repoRoot, 'scripts', 'release', 'deterministic-zip.js')
const verifyModulePath = path.join(repoRoot, 'scripts', 'release', 'verify-release-artifact.js')
const VERSION = '0.82.0'
const TAG = `v${VERSION}`
const SOURCE_SHA = '1234567890abcdef1234567890abcdef12345678'

function write(root, relativePath, content) {
  const filePath = path.join(root, relativePath)
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, content)
}

function writeJson(root, relativePath, value) {
  write(root, relativePath, `${JSON.stringify(value, null, 2)}\n`)
}

function packageFixture(root, options = {}) {
  writeJson(root, 'haxelib.json', {
    name: 'reflaxe.rust',
    version: options.version || VERSION,
    releasenote: `v${options.version || VERSION}: See GitHub Releases`,
    classPath: 'src'
  })
  writeJson(root, 'release-metadata.json', {
    schemaVersion: 1,
    version: VERSION,
    tag: TAG,
    sourceCommit: SOURCE_SHA
  })
  write(root, 'README.md', '# fixture\n')
  write(root, 'LICENSE', 'fixture license\n')
  write(root, 'extraParams.hxml', '# fixture\n')
  write(root, 'src/reflaxe/rust/CompilerInit.hx', 'package reflaxe.rust; class CompilerInit {}\n')
  write(root, 'src/haxe/Exception.cross.hx', 'package haxe; class Exception {}\n')
  write(root, 'runtime/hxrt/Cargo.toml', '[package]\nname = "hxrt"\n')
  write(root, 'vendor/reflaxe/src/reflaxe/ReflectCompiler.hx', 'package reflaxe; class ReflectCompiler {}\n')
}

function sha256(filePath) {
  return crypto.createHash('sha256').update(fs.readFileSync(filePath)).digest('hex')
}

function touchTree(root, milliseconds) {
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const entryPath = path.join(root, entry.name)
    if (entry.isDirectory()) touchTree(entryPath, milliseconds + 1000)
    fs.utimesSync(entryPath, milliseconds / 1000, milliseconds / 1000)
  }
}

function expectThrow(callback, pattern) {
  assert.throws(callback, pattern)
}

function main() {
  assert(fs.existsSync(zipModulePath), 'deterministic ZIP module must exist')
  assert(fs.existsSync(verifyModulePath), 'release artifact verifier must exist')
  const zipApi = require(zipModulePath)
  const verifyApi = require(verifyModulePath)

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-release-artifact-'))
  try {
    const left = path.join(temp, 'left')
    const right = path.join(temp, 'right')
    packageFixture(left)
    packageFixture(right)
    touchTree(left, Date.UTC(2020, 0, 1))
    touchTree(right, Date.UTC(2030, 5, 1))
    fs.chmodSync(path.join(left, 'README.md'), 0o600)
    fs.chmodSync(path.join(right, 'README.md'), 0o644)

    const leftZip = path.join(temp, 'left.zip')
    const rightZip = path.join(temp, 'right.zip')
    execFileSync(process.execPath, [zipModulePath, left, leftZip], {
      env: { ...process.env, TZ: 'America/Mexico_City' },
      stdio: 'pipe'
    })
    execFileSync(process.execPath, [zipModulePath, right, rightZip], {
      env: { ...process.env, TZ: 'UTC' },
      stdio: 'pipe'
    })
    assert.strictEqual(sha256(leftZip), sha256(rightZip), 'ZIP bytes must ignore source mtimes and modes')

    const result = verifyApi.verifyReleaseArtifact({
      zipPath: leftZip,
      version: VERSION,
      tag: TAG,
      sourceCommit: SOURCE_SHA
    })
    assert.strictEqual(result.sha256, sha256(leftZip))
    assert.strictEqual(result.size, fs.statSync(leftZip).size)
    assert(result.entries.includes('release-metadata.json'))
    assert.deepStrictEqual(
      [...result.entries].sort(zipApi.compareEntryNames),
      result.entries,
      'archive entries must be sorted'
    )

    const missingRoot = path.join(temp, 'missing-root')
    packageFixture(missingRoot)
    fs.rmSync(path.join(missingRoot, 'runtime'), { recursive: true })
    const missingZip = path.join(temp, 'missing.zip')
    zipApi.createDeterministicZip(missingRoot, missingZip)
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: missingZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA
        }),
      /required archive entry is missing: runtime\/hxrt\/Cargo\.toml/
    )

    const wrongVersionRoot = path.join(temp, 'wrong-version')
    packageFixture(wrongVersionRoot, { version: '0.81.3' })
    const wrongVersionZip = path.join(temp, 'wrong-version.zip')
    zipApi.createDeterministicZip(wrongVersionRoot, wrongVersionZip)
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: wrongVersionZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA
        }),
      /packaged haxelib version 0\.81\.3 does not match 0\.82\.0/
    )

    const unsafeZip = path.join(temp, 'unsafe.zip')
    fs.writeFileSync(
      unsafeZip,
      Buffer.from(zipSync({ '../escape.txt': strToU8('escape'), 'haxelib.json': strToU8('{}') }))
    )
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: unsafeZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA
        }),
      /unsafe archive entry/
    )

    expectThrow(() => zipApi.validateEntryNames(['a.txt', 'a.txt']), /duplicate archive entry/)
    expectThrow(() => zipApi.validateEntryNames(['/absolute.txt']), /unsafe archive entry/)
    expectThrow(() => zipApi.validateEntryNames(['windows\\escape.txt']), /unsafe archive entry/)

    const symlinkRoot = path.join(temp, 'symlink')
    packageFixture(symlinkRoot)
    fs.symlinkSync(path.join(symlinkRoot, 'README.md'), path.join(symlinkRoot, 'linked-readme'))
    expectThrow(() => zipApi.createDeterministicZip(symlinkRoot, path.join(temp, 'symlink.zip')), /symbolic link/)

    console.log('[release-artifact-test] OK')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

main()
