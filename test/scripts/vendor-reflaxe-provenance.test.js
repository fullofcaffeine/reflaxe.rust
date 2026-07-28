#!/usr/bin/env node

const assert = require('assert')
const crypto = require('crypto')
const { execFileSync, spawnSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const root = path.resolve(__dirname, '..', '..')
const checker = path.join(root, 'scripts', 'ci', 'vendor-reflaxe-provenance.js')

function run(repositoryRoot, upstreamDir = null) {
  const args = [checker, '--root', repositoryRoot]
  if (upstreamDir) args.push('--upstream-dir', upstreamDir)
  return spawnSync(process.execPath, args, { encoding: 'utf8' })
}

function expectFailure(repositoryRoot, pattern, upstreamDir = null) {
  const result = run(repositoryRoot, upstreamDir)
  assert.notStrictEqual(result.status, 0, 'mutated provenance fixture must fail')
  assert.match(`${result.stdout}${result.stderr}`, pattern)
}

function copyFixture(parent, name) {
  const fixture = path.join(parent, name)
  fs.mkdirSync(path.join(fixture, 'vendor'), { recursive: true })
  fs.cpSync(path.join(root, 'vendor', 'reflaxe'), path.join(fixture, 'vendor', 'reflaxe'), {
    recursive: true
  })
  return fixture
}

function readManifest(repositoryRoot) {
  return JSON.parse(fs.readFileSync(path.join(repositoryRoot, 'vendor', 'reflaxe', 'provenance.json'), 'utf8'))
}

function writeManifest(repositoryRoot, manifest) {
  fs.writeFileSync(
    path.join(repositoryRoot, 'vendor', 'reflaxe', 'provenance.json'),
    `${JSON.stringify(manifest, null, 2)}\n`
  )
}

function filesBelow(directory, prefix = '') {
  const result = []
  for (const entry of fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name
    if (entry.isDirectory()) result.push(...filesBelow(path.join(directory, entry.name), relative))
    else if (entry.isFile()) result.push(relative)
  }
  return result
}

function treeDigest(repositoryRoot, scopes) {
  const vendor = path.join(repositoryRoot, 'vendor', 'reflaxe')
  const files = scopes
    .flatMap((scope) => {
      const absolute = path.join(vendor, scope)
      return fs.statSync(absolute).isDirectory() ? filesBelow(absolute, scope) : [scope]
    })
    .sort()
  const hash = crypto.createHash('sha256')
  for (const file of files) {
    hash.update(file)
    hash.update('\0')
    hash.update(fs.readFileSync(path.join(vendor, file)))
    hash.update('\0')
  }
  return hash.digest('hex')
}

function git(directory, args) {
  return execFileSync('git', ['-C', directory, ...args], { encoding: 'utf8' }).trim()
}

function syntheticUpstream(parent, repositoryRoot) {
  const upstream = path.join(parent, 'upstream')
  fs.mkdirSync(upstream)
  const vendor = path.join(repositoryRoot, 'vendor', 'reflaxe')
  fs.cpSync(path.join(vendor, 'Run.hx'), path.join(upstream, 'Run.hx'))
  fs.cpSync(path.join(vendor, 'src'), path.join(upstream, 'src'), { recursive: true })
  fs.copyFileSync(path.join(vendor, 'LICENSE'), path.join(upstream, 'LICENSE'))
  git(upstream, ['init', '-q'])
  git(upstream, ['apply', '-R', path.join(vendor, 'reflaxe-rust.patch')])
  git(upstream, ['add', '.'])
  git(upstream, [
    '-c',
    'user.name=Provenance Test',
    '-c',
    'user.email=provenance@example.invalid',
    'commit',
    '-q',
    '-m',
    'synthetic upstream base'
  ])
  return upstream
}

function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'vendor-reflaxe-provenance-test-'))
  try {
    const clean = copyFixture(temp, 'clean')
    assert.strictEqual(run(clean).status, 0, 'unaltered fixture must pass')

    const patchDrift = copyFixture(temp, 'patch-drift')
    fs.appendFileSync(path.join(patchDrift, 'vendor', 'reflaxe', 'reflaxe-rust.patch'), '\n')
    expectFailure(patchDrift, /patch digest is stale/)

    const treeDrift = copyFixture(temp, 'tree-drift')
    fs.appendFileSync(
      path.join(treeDrift, 'vendor', 'reflaxe', 'src', 'reflaxe', 'ReflectCompiler.hx'),
      '\n'
    )
    expectFailure(treeDrift, /source tree digest is stale/)

    const changedFilesDrift = copyFixture(temp, 'changed-files-drift')
    const changedManifest = readManifest(changedFilesDrift)
    changedManifest.localPatch.changedFiles.pop()
    writeManifest(changedFilesDrift, changedManifest)
    expectFailure(changedFilesDrift, /changed-file list does not match/)

    const groupDrift = copyFixture(temp, 'group-drift')
    const groupManifest = readManifest(groupDrift)
    groupManifest.localPatch.changeGroups[0].files.push(groupManifest.localPatch.changedFiles[1])
    writeManifest(groupDrift, groupManifest)
    expectFailure(groupDrift, /change groups do not cover/)

    const rootDrift = copyFixture(temp, 'root-drift')
    fs.writeFileSync(path.join(rootDrift, 'vendor', 'reflaxe', 'UNRECORDED.txt'), 'unexpected\n')
    expectFailure(rootDrift, /root-entry inventory differs/)

    const nestedRootDrift = copyFixture(temp, 'nested-root-drift')
    fs.mkdirSync(path.join(nestedRootDrift, 'vendor', 'reflaxe', 'UNRECORDED'))
    fs.writeFileSync(
      path.join(nestedRootDrift, 'vendor', 'reflaxe', 'UNRECORDED', 'payload.txt'),
      'unexpected\n'
    )
    expectFailure(nestedRootDrift, /root-entry inventory differs/)

    const licenseDrift = copyFixture(temp, 'license-drift')
    fs.appendFileSync(path.join(licenseDrift, 'vendor', 'reflaxe', 'LICENSE'), '\nchanged\n')
    expectFailure(licenseDrift, /license digest is stale/)

    const narrowedScope = copyFixture(temp, 'narrowed-scope')
    const narrowedManifest = readManifest(narrowedScope)
    narrowedManifest.localPatch.scope = ['src']
    narrowedManifest.localPatch.vendoredTreeSha256 = treeDigest(narrowedScope, ['src'])
    writeManifest(narrowedScope, narrowedManifest)
    fs.appendFileSync(path.join(narrowedScope, 'vendor', 'reflaxe', 'Run.hx'), '\nunchecked change\n')
    expectFailure(narrowedScope, /reconstruction scope must exactly cover Run\.hx and src/)

    const contradictorySurface = copyFixture(temp, 'contradictory-surface')
    const contradictoryManifest = readManifest(contradictorySurface)
    contradictoryManifest.vendoredSurface.copiedFromUpstream = ['LICENSE', 'src']
    writeManifest(contradictorySurface, contradictoryManifest)
    expectFailure(contradictorySurface, /copied upstream surface must exactly cover LICENSE, Run\.hx, and src/)

    const nestedLicenseDrift = copyFixture(temp, 'nested-license-drift')
    const nestedLicense = JSON.parse(
      fs.readFileSync(path.join(nestedLicenseDrift, 'vendor', 'reflaxe', 'haxelib.json'), 'utf8')
    )
    nestedLicense.license = 'Apache-2.0'
    fs.writeFileSync(
      path.join(nestedLicenseDrift, 'vendor', 'reflaxe', 'haxelib.json'),
      `${JSON.stringify(nestedLicense, null, 2)}\n`
    )
    expectFailure(nestedLicenseDrift, /Reflaxe haxelib metadata contradicts provenance: license differs/)

    const nestedUrlDrift = copyFixture(temp, 'nested-url-drift')
    const nestedUrl = JSON.parse(
      fs.readFileSync(path.join(nestedUrlDrift, 'vendor', 'reflaxe', 'haxelib.json'), 'utf8')
    )
    nestedUrl.url = 'https://example.invalid/not-reflaxe'
    fs.writeFileSync(
      path.join(nestedUrlDrift, 'vendor', 'reflaxe', 'haxelib.json'),
      `${JSON.stringify(nestedUrl, null, 2)}\n`
    )
    expectFailure(nestedUrlDrift, /Reflaxe haxelib metadata contradicts provenance: repository differs/)

    const renamedComponent = copyFixture(temp, 'renamed-component')
    const renamedManifest = readManifest(renamedComponent)
    renamedManifest.component.name = 'Different framework'
    writeManifest(renamedComponent, renamedManifest)
    expectFailure(renamedComponent, /Reflaxe provenance component name must be Reflaxe/)

    const missingLicenseAgreement = copyFixture(temp, 'missing-license-agreement')
    const missingLicenseManifest = readManifest(missingLicenseAgreement)
    delete missingLicenseManifest.component.license
    writeManifest(missingLicenseAgreement, missingLicenseManifest)
    const missingLicenseHaxelibPath = path.join(
      missingLicenseAgreement,
      'vendor',
      'reflaxe',
      'haxelib.json'
    )
    const missingLicenseHaxelib = JSON.parse(
      fs.readFileSync(missingLicenseHaxelibPath, 'utf8')
    )
    delete missingLicenseHaxelib.license
    fs.writeFileSync(
      missingLicenseHaxelibPath,
      `${JSON.stringify(missingLicenseHaxelib, null, 2)}\n`
    )
    expectFailure(
      missingLicenseAgreement,
      /Reflaxe provenance license must be a non-empty string/
    )

    const missingRepositoryAgreement = copyFixture(temp, 'missing-repository-agreement')
    const missingRepositoryManifest = readManifest(missingRepositoryAgreement)
    delete missingRepositoryManifest.component.upstreamRepository
    writeManifest(missingRepositoryAgreement, missingRepositoryManifest)
    const missingRepositoryHaxelibPath = path.join(
      missingRepositoryAgreement,
      'vendor',
      'reflaxe',
      'haxelib.json'
    )
    const missingRepositoryHaxelib = JSON.parse(
      fs.readFileSync(missingRepositoryHaxelibPath, 'utf8')
    )
    delete missingRepositoryHaxelib.url
    fs.writeFileSync(
      missingRepositoryHaxelibPath,
      `${JSON.stringify(missingRepositoryHaxelib, null, 2)}\n`
    )
    expectFailure(
      missingRepositoryAgreement,
      /Reflaxe provenance repository must be a non-empty string/
    )

    const reconstruction = copyFixture(temp, 'reconstruction')
    const upstream = syntheticUpstream(temp, reconstruction)
    const reconstructionManifest = readManifest(reconstruction)
    reconstructionManifest.upstream.baseCommit = git(upstream, ['rev-parse', 'HEAD'])
    writeManifest(reconstruction, reconstructionManifest)
    assert.strictEqual(run(reconstruction, upstream).status, 0, 'synthetic upstream reconstruction must pass')

    fs.appendFileSync(path.join(upstream, 'src', 'reflaxe', 'ReflectCompiler.hx'), '\nincompatible\n')
    git(upstream, ['add', '.'])
    git(upstream, [
      '-c',
      'user.name=Provenance Test',
      '-c',
      'user.email=provenance@example.invalid',
      'commit',
      '-q',
      '-m',
      'incompatible base'
    ])
    reconstructionManifest.upstream.baseCommit = git(upstream, ['rev-parse', 'HEAD'])
    writeManifest(reconstruction, reconstructionManifest)
    expectFailure(reconstruction, /patch does not apply|patch failed|error:/i, upstream)

    console.log('[vendor-reflaxe-provenance.test] OK')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

main()
