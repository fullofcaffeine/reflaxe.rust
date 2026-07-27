#!/usr/bin/env node

const crypto = require('crypto')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')

let root = path.resolve(__dirname, '..', '..')
let vendorRoot = path.join(root, 'vendor', 'reflaxe')
let manifestPath = path.join(vendorRoot, 'provenance.json')

function fail(message) {
  throw new Error(message)
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')
}

function run(command, args, options = {}) {
  return execFileSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options })
}

function filesBelow(directory, prefix = '') {
  const result = []
  for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name
    if (entry.isDirectory()) result.push(...filesBelow(path.join(directory, entry.name), relative))
    else if (entry.isFile()) result.push(relative)
    else fail(`unsupported filesystem entry in vendored source: ${relative}`)
  }
  return result
}

function patchChangedFiles(patchText) {
  return [...patchText.matchAll(/^diff --git a\/(.+?) b\/(.+)$/gm)].map((match) => {
    if (match[1] !== match[2]) fail(`vendored patch contains a rename: ${match[1]} -> ${match[2]}`)
    return match[2]
  })
}

function vendoredTreeDigest(scopes) {
  const files = scopes.flatMap((scope) => {
    const absolute = path.join(vendorRoot, scope)
    return fs.statSync(absolute).isDirectory()
      ? filesBelow(absolute, scope)
      : [scope]
  })
  const hash = crypto.createHash('sha256')
  for (const file of files.sort()) {
    hash.update(file)
    hash.update('\0')
    hash.update(fs.readFileSync(path.join(vendorRoot, file)))
    hash.update('\0')
  }
  return hash.digest('hex')
}

function verifyAgainstUpstream(manifest, upstreamDir) {
  const base = manifest.upstream.baseCommit
  run('git', ['-C', upstreamDir, 'cat-file', '-e', `${base}^{commit}`])
  const upstreamLicense = run('git', ['-C', upstreamDir, 'show', `${base}:LICENSE`])
  if (crypto.createHash('sha256').update(upstreamLicense).digest('hex') !== sha256(path.join(vendorRoot, 'LICENSE'))) {
    fail('vendored Reflaxe license differs from the recorded upstream base')
  }
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-provenance-'))
  try {
    const archive = path.join(temp, 'base.tar')
    execFileSync('git', ['-C', upstreamDir, 'archive', `--output=${archive}`, base, ...manifest.localPatch.scope])
    execFileSync('tar', ['-xf', archive, '-C', temp])
    execFileSync('git', ['-C', temp, 'init', '-q'])
    execFileSync('git', ['-C', temp, 'apply', path.join(vendorRoot, manifest.localPatch.file)])

    for (const scope of manifest.localPatch.scope) {
      const expected = path.join(vendorRoot, scope)
      const actual = path.join(temp, scope)
      if (fs.statSync(expected).isDirectory()) {
        const expectedFiles = filesBelow(expected)
        const actualFiles = filesBelow(actual)
        if (JSON.stringify(actualFiles) !== JSON.stringify(expectedFiles)) {
          fail(`reconstructed ${scope} file inventory differs from the vendored tree`)
        }
        for (const relative of expectedFiles) {
          if (sha256(path.join(actual, relative)) !== sha256(path.join(expected, relative))) {
            fail(`reconstructed file differs from the vendored tree: ${scope}/${relative}`)
          }
        }
      } else if (sha256(actual) !== sha256(expected)) {
        fail(`reconstructed file differs from the vendored tree: ${scope}`)
      }
    }
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

function main() {
  const args = process.argv.slice(2)
  let upstreamDir = null
  for (let index = 0; index < args.length; index += 2) {
    const flag = args[index]
    const value = args[index + 1]
    if (!value || (flag !== '--root' && flag !== '--upstream-dir')) {
      fail('usage: vendor-reflaxe-provenance.js [--root /path/to/repo] [--upstream-dir /path/to/reflaxe]')
    }
    if (flag === '--root') {
      root = path.resolve(value)
      vendorRoot = path.join(root, 'vendor', 'reflaxe')
      manifestPath = path.join(vendorRoot, 'provenance.json')
    } else {
      upstreamDir = path.resolve(value)
    }
  }

  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
  if (manifest.schemaVersion !== 1) fail('unsupported Reflaxe provenance schema')
  if (!/^[0-9a-f]{40}$/.test(manifest.upstream.baseCommit)) fail('upstream base must be an exact commit')
  const licensePath = path.join(vendorRoot, manifest.component.licenseFile)
  if (!fs.existsSync(licensePath)) fail('vendored Reflaxe license is missing')
  if (sha256(licensePath) !== manifest.component.licenseSha256) fail('vendored Reflaxe license digest is stale')

  const patchPath = path.join(vendorRoot, manifest.localPatch.file)
  if (sha256(patchPath) !== manifest.localPatch.sha256) fail('vendored Reflaxe patch digest is stale')
  if (vendoredTreeDigest(manifest.localPatch.scope) !== manifest.localPatch.vendoredTreeSha256) {
    fail('vendored Reflaxe source tree digest is stale')
  }
  const patchFiles = patchChangedFiles(fs.readFileSync(patchPath, 'utf8'))
  if (JSON.stringify(patchFiles) !== JSON.stringify(manifest.localPatch.changedFiles)) {
    fail('vendored Reflaxe changed-file list does not match the exact patch')
  }
  const groupedFiles = manifest.localPatch.changeGroups
    .flatMap((group) => {
      if (!group.behavior || !Array.isArray(group.tests) || group.tests.length === 0) {
        fail(`vendored Reflaxe change group lacks behavior or tests: ${group.name}`)
      }
      return group.files
    })
    .sort()
  if (JSON.stringify(groupedFiles) !== JSON.stringify([...manifest.localPatch.changedFiles].sort())) {
    fail('vendored Reflaxe change groups do not cover every changed source file exactly once')
  }
  for (const file of manifest.localPatch.changedFiles) {
    if (!fs.existsSync(path.join(vendorRoot, file))) fail(`patched vendored file is missing: ${file}`)
  }
  const rootEntries = fs
    .readdirSync(vendorRoot, { withFileTypes: true })
    .map((entry) => entry.name)
    .sort()
  const recordedRootEntries = [
    ...manifest.vendoredSurface.copiedFromUpstream.filter((entry) => !entry.includes('/')),
    ...manifest.vendoredSurface.localRecords
  ].sort()
  if (JSON.stringify(rootEntries) !== JSON.stringify(recordedRootEntries)) {
    fail('vendored Reflaxe root-entry inventory differs from provenance.json')
  }

  if (upstreamDir !== null) verifyAgainstUpstream(manifest, upstreamDir)
  console.log(
    `[vendor-reflaxe-provenance] OK: ${manifest.upstream.baseCommit}, ${patchFiles.length} changed source files`
  )
}

try {
  main()
} catch (error) {
  console.error(`[vendor-reflaxe-provenance] ERROR: ${error.message}`)
  process.exit(1)
}
