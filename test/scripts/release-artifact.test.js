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
const licenseArtifactModulePath = path.join(repoRoot, 'scripts', 'release', 'generate-license-artifacts.js')
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
    classPath: 'src',
    license: 'GPL-3.0'
  })
  writeJson(root, 'release-metadata.json', {
    schemaVersion: 1,
    version: VERSION,
    tag: TAG,
    sourceCommit: SOURCE_SHA
  })
  write(root, 'README.md', '# fixture\n')
  write(root, 'LICENSE', 'fixture license\n')
  for (const [name, content] of require(licenseArtifactModulePath).buildArtifacts(VERSION)) {
    write(root, name, content)
  }
  write(root, 'extraParams.hxml', '# fixture\n')
  write(root, 'src/reflaxe/rust/CompilerInit.hx', 'package reflaxe.rust; class CompilerInit {}\n')
  write(root, 'src/haxe/Exception.cross.hx', 'package haxe; class Exception {}\n')
  write(root, 'runtime/hxrt/Cargo.toml', '[package]\nname = "hxrt"\n')
  write(root, 'vendor/reflaxe/LICENSE', 'MIT License\n')
  const fixturePatch = 'fixture patch\n'
  writeJson(root, 'vendor/reflaxe/provenance.json', {
    schemaVersion: 1,
    component: 'Reflaxe',
    upstream: {
      repository: 'https://github.com/SomeRanDev/reflaxe.git',
      baseCommit: '3ec70a83936a8919e5441e03a6fdc1b17ec79881'
    },
    localPatch: {
      file: 'reflaxe-rust.patch',
      sha256: crypto.createHash('sha256').update(fixturePatch).digest('hex')
    }
  })
  write(root, 'vendor/reflaxe/reflaxe-rust.patch', fixturePatch)
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
  const licenseApi = require(licenseArtifactModulePath)
  const releaseComponents = JSON.parse(
    fs.readFileSync(path.join(repoRoot, 'docs', 'release-package-components.json'), 'utf8')
  )
  for (const requiredId of licenseApi.REQUIRED_COMPONENT_IDS) {
    expectThrow(
      () =>
        licenseApi.validateRequiredComponentIds({
          ...releaseComponents,
          components: releaseComponents.components.filter((component) => component.id !== requiredId)
        }),
      new RegExp(`missing required component: ${requiredId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`)
    )
  }
  const stdlibComponent = releaseComponents.components.find(
    (component) => component.id === 'haxe-standard-library-derived-files'
  )
  const movedStdlib = licenseApi.resolveStdlibComponent(stdlibComponent, {
    upstreamStdVersion: '9.8.7',
    upstreamRepository: 'https://example.invalid/haxe',
    license: {
      id: 'MIT',
      sourceFile: 'reviewed-license.txt',
      sha256: 'a'.repeat(64)
    }
  })
  assert.strictEqual(movedStdlib.version, '9.8.7')
  assert.strictEqual(movedStdlib.source, 'https://example.invalid/haxe/tree/9.8.7')
  assert.strictEqual(movedStdlib.licenseSourceFile, 'reviewed-license.txt')
  const firstSbom = JSON.parse(licenseApi.buildArtifacts('1.2.34').get('release-sbom.json'))
  const secondSbom = JSON.parse(licenseApi.buildArtifacts('12.3.4').get('release-sbom.json'))
  assert(!('serialNumber' in firstSbom), 'deterministic SBOM must omit a fabricated UUID serial number')
  assert.notDeepStrictEqual(firstSbom, secondSbom, 'different package versions must produce different SBOMs')
  const cargoRequirement = firstSbom.components.find((component) =>
    component.properties?.some((property) => property.name === 'reflaxe.rust:version-requirement')
  )
  assert(cargoRequirement, 'SBOM must inventory Cargo requirements')
  assert(!('version' in cargoRequirement), 'an unresolved Cargo requirement must not look like an installed version')
  assert(
    cargoRequirement['bom-ref'].startsWith('urn:reflaxe-rust:cargo-requirement:'),
    'an unresolved Cargo requirement must not use an exact package coordinate'
  )

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-release-artifact-'))
  try {
    const cargoFixture = path.join(temp, 'cargo-metadata')
    write(
      cargoFixture,
      'Cargo.toml',
      `[package]
name = "cargo-inventory-fixture"
version = "0.0.0"
edition = "2021"

[lib]
path = "src/lib.rs"

[dependencies.serde]
version = "1"
optional = true

[build-dependencies]
cc = "1"

[target.'cfg(unix)'.dependencies]
libc = "0.2"
`
    )
    write(cargoFixture, 'src/lib.rs', '')
    const parsedCargo = licenseApi.cargoRequirements(path.join(cargoFixture, 'Cargo.toml'))
    assert(parsedCargo.some((entry) => entry.name === 'serde' && entry.optional))
    assert(parsedCargo.some((entry) => entry.name === 'cc' && entry.kind === 'build'))
    assert(parsedCargo.some((entry) => entry.name === 'libc' && entry.target === 'cfg(unix)'))

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
      sourceCommit: SOURCE_SHA,
      sourceRoot: left
    })
    assert.strictEqual(result.sha256, sha256(leftZip))
    assert.strictEqual(result.size, fs.statSync(leftZip).size)
    assert(result.entries.includes('release-metadata.json'))
    assert(result.entries.includes('release-sbom.json'))
    assert(result.entries.includes('THIRD_PARTY_NOTICES.md'))
    assert(result.entries.includes('vendor/reflaxe/LICENSE'))
    assert(result.entries.includes('vendor/reflaxe/provenance.json'))
    assert(result.entries.includes('vendor/reflaxe/reflaxe-rust.patch'))
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
          sourceCommit: SOURCE_SHA,
          sourceRoot: missingRoot
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
          sourceCommit: SOURCE_SHA,
          sourceRoot: wrongVersionRoot
        }),
      /packaged haxelib version 0\.81\.3 does not match 0\.82\.0/
    )

    const badPatchRoot = path.join(temp, 'bad-patch')
    packageFixture(badPatchRoot)
    write(badPatchRoot, 'vendor/reflaxe/reflaxe-rust.patch', 'different patch\n')
    const badPatchZip = path.join(temp, 'bad-patch.zip')
    zipApi.createDeterministicZip(badPatchRoot, badPatchZip)
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: badPatchZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: badPatchRoot
        }),
      /vendored Reflaxe patch digest does not match/
    )

    const badSbomRoot = path.join(temp, 'bad-sbom')
    packageFixture(badSbomRoot)
    const badSbom = JSON.parse(fs.readFileSync(path.join(badSbomRoot, 'release-sbom.json'), 'utf8'))
    badSbom.components = badSbom.components.filter(
      (component) => component.name !== 'Haxe Standard Library derived files'
    )
    writeJson(badSbomRoot, 'release-sbom.json', badSbom)
    const badSbomZip = path.join(temp, 'bad-sbom.zip')
    zipApi.createDeterministicZip(badSbomRoot, badSbomZip)
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: badSbomZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: badSbomRoot
        }),
      /archive entry differs from generated license evidence: release-sbom\.json/
    )

    const missingLicenseRoot = path.join(temp, 'missing-license')
    packageFixture(missingLicenseRoot)
    fs.rmSync(path.join(missingLicenseRoot, 'vendor/reflaxe/LICENSE'))
    const missingLicenseZip = path.join(temp, 'missing-license.zip')
    zipApi.createDeterministicZip(missingLicenseRoot, missingLicenseZip)
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: missingLicenseZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: missingLicenseRoot
        }),
      /required archive entry is missing: vendor\/reflaxe\/LICENSE/
    )

    const cargoSourceRoot = path.join(temp, 'cargo-source')
    const badCargoRoot = path.join(temp, 'bad-cargo')
    packageFixture(cargoSourceRoot)
    fs.cpSync(cargoSourceRoot, badCargoRoot, { recursive: true })
    write(
      badCargoRoot,
      'runtime/hxrt/Cargo.toml',
      `${fs.readFileSync(path.join(badCargoRoot, 'runtime/hxrt/Cargo.toml'), 'utf8')}\nuninventoried = "9"\n`
    )
    const badCargoZip = path.join(temp, 'bad-cargo.zip')
    zipApi.createDeterministicZip(badCargoRoot, badCargoZip)
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: badCargoZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: cargoSourceRoot
        }),
      /archive entry differs from the reviewed source: runtime\/hxrt\/Cargo\.toml/
    )

    const licenseSourceRoot = path.join(temp, 'license-source')
    const badRootLicense = path.join(temp, 'bad-root-license')
    packageFixture(licenseSourceRoot)
    fs.cpSync(licenseSourceRoot, badRootLicense, { recursive: true })
    write(badRootLicense, 'LICENSE', 'forged root license\n')
    const badRootLicenseZip = path.join(temp, 'bad-root-license.zip')
    zipApi.createDeterministicZip(badRootLicense, badRootLicenseZip)
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: badRootLicenseZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: licenseSourceRoot
        }),
      /archive entry differs from the reviewed source: LICENSE/
    )

    const metadataSourceRoot = path.join(temp, 'metadata-source')
    const badMetadataRoot = path.join(temp, 'bad-metadata')
    packageFixture(metadataSourceRoot)
    fs.cpSync(metadataSourceRoot, badMetadataRoot, { recursive: true })
    const badHaxelib = JSON.parse(fs.readFileSync(path.join(badMetadataRoot, 'haxelib.json'), 'utf8'))
    delete badHaxelib.license
    writeJson(badMetadataRoot, 'haxelib.json', badHaxelib)
    const badMetadataZip = path.join(temp, 'bad-metadata.zip')
    zipApi.createDeterministicZip(badMetadataRoot, badMetadataZip)
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: badMetadataZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: metadataSourceRoot
        }),
      /packaged haxelib metadata differs from the reviewed source/
    )

    const vendorSourceRoot = path.join(temp, 'vendor-source')
    const badVendorRoot = path.join(temp, 'bad-vendor')
    packageFixture(vendorSourceRoot)
    fs.cpSync(vendorSourceRoot, badVendorRoot, { recursive: true })
    write(
      badVendorRoot,
      'vendor/reflaxe/src/reflaxe/ReflectCompiler.hx',
      'package reflaxe; class ForgedReflectCompiler {}\n'
    )
    const badVendorZip = path.join(temp, 'bad-vendor.zip')
    zipApi.createDeterministicZip(badVendorRoot, badVendorZip)
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: badVendorZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: vendorSourceRoot
        }),
      /archive entry differs from the reviewed source: vendor\/reflaxe\/src\/reflaxe\/ReflectCompiler\.hx/
    )

    const badNoticeRoot = path.join(temp, 'bad-notice')
    packageFixture(badNoticeRoot)
    write(badNoticeRoot, 'THIRD_PARTY_NOTICES.md', '# incomplete notices\n')
    const badNoticeZip = path.join(temp, 'bad-notice.zip')
    zipApi.createDeterministicZip(badNoticeRoot, badNoticeZip)
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: badNoticeZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: badNoticeRoot
        }),
      /archive entry differs from generated license evidence: THIRD_PARTY_NOTICES\.md/
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
