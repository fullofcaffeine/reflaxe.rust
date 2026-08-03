#!/usr/bin/env node

const assert = require('assert')
const crypto = require('crypto')
const { execFileSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
// Test-only archive construction deliberately stays independent from the production ZIP writer.
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
    url: 'https://github.com/fullofcaffeine/reflaxe.rust',
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
  const reflaxeLicense = 'MIT License\n'
  write(root, 'vendor/reflaxe/LICENSE', reflaxeLicense)
  writeJson(root, 'vendor/reflaxe/haxelib.json', {
    name: 'reflaxe',
    url: 'https://github.com/SomeRanDev/reflaxe',
    license: 'MIT',
    version: '4.0.0-beta'
  })
  const fixturePatch = 'fixture patch\n'
  writeJson(root, 'vendor/reflaxe/provenance.json', {
    schemaVersion: 1,
    component: {
      name: 'Reflaxe',
      upstreamRepository: 'https://github.com/SomeRanDev/reflaxe.git',
      license: 'MIT',
      licenseFile: 'LICENSE',
      licenseSha256: crypto.createHash('sha256').update(reflaxeLicense).digest('hex')
    },
    upstream: {
      baseCommit: '3ec70a83936a8919e5441e03a6fdc1b17ec79881'
    },
    localPatch: {
      file: 'reflaxe-rust.patch',
      sha256: crypto.createHash('sha256').update(fixturePatch).digest('hex')
    }
  })
  write(root, 'vendor/reflaxe/reflaxe-rust.patch', fixturePatch)
  write(root, 'vendor/reflaxe/src/reflaxe/ReflectCompiler.hx', 'package reflaxe; class ReflectCompiler {}\n')
  write(
    root,
    'provenance/stdlib-provenance-ledger.json',
    fs.readFileSync(path.join(repoRoot, 'docs', 'stdlib-provenance-ledger.json'))
  )
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
  for (const relative of [
    'scripts/release/deterministic-zip.js',
    'scripts/release/prepare-package-metadata.js',
    'scripts/release/semantic-version.js',
    'scripts/release/verify-release-artifact.js'
  ]) {
    const source = fs.readFileSync(path.join(repoRoot, relative), 'utf8')
    assert(!/require\(['"](?:fflate|semver)['"]\)/.test(source), `${relative} must not load artifact authority from node_modules`)
  }
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
  for (const [id, field, value, pattern] of [
    ['reflaxe', 'name', 'Different framework', /reflaxe name must be exactly Reflaxe/],
    [
      'reflaxe',
      'provenanceFile',
      'local/alternate.json',
      /reflaxe provenanceFile must be exactly vendor\/reflaxe\/provenance\.json/
    ],
    [
      'haxe-standard-library-derived-files',
      'stdlibProvenanceFile',
      'local/alternate.json',
      /stdlibProvenanceFile must be exactly docs\/stdlib-provenance-ledger\.json/
    ],
    [
      'reflaxe-rust',
      'source',
      'https://example.invalid/different-product',
      /reflaxe-rust source must be exactly https:\/\/github\.com\/fullofcaffeine\/reflaxe\.rust/
    ]
  ]) {
    const mutation = JSON.parse(JSON.stringify(releaseComponents))
    mutation.components.find((component) => component.id === id)[field] = value
    expectThrow(() => licenseApi.validateRequiredComponentIds(mutation), pattern)
  }
	for (const [id, field, value] of [
		['haxe-standard-library-derived-files', 'licenseText', 'FORGED INLINE HAXE LICENSE TEXT'],
		['haxe-standard-library-derived-files', 'licenseSourceFile', 'docs/local-license.txt'],
		['haxe-standard-library-derived-files', 'licenseFile', 'docs/local-license.txt'],
		['haxe-standard-library-derived-files', 'licenseSha256', 'a'.repeat(64)],
		['reflaxe', 'licenseText', 'FORGED INLINE REFLAXE LICENSE TEXT'],
		['reflaxe', 'licenseSourceFile', 'docs/local-license.txt'],
		['reflaxe', 'licenseFile', 'docs/local-license.txt'],
		['reflaxe', 'licenseSha256', 'a'.repeat(64)]
	]) {
		const mutation = JSON.parse(JSON.stringify(releaseComponents))
		mutation.components.find((component) => component.id === id)[field] = value
		expectThrow(
			() => licenseApi.validateRequiredComponentIds(mutation),
			new RegExp(`${id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} must not override reviewed license bytes`)
		)
	}
	const duplicateProjectName = JSON.parse(JSON.stringify(releaseComponents))
	duplicateProjectName.components.push({
		id: 'duplicate-project-name',
		name: 'reflaxe.rust',
		kind: 'library'
	})
	expectThrow(
		() => licenseApi.validateRequiredComponentIds(duplicateProjectName),
		/release component inventory must contain exactly one reflaxe\.rust component/
	)
  for (const externalLink of [
    'https://github.com/fullofcaffeine/reflaxe.rust/tree/main/docs/stdlib-provenance-ledger.json',
    'HTTPS://github.com/fullofcaffeine/reflaxe.rust/tree/main/docs/stdlib-provenance-ledger.json',
    '//github.com/fullofcaffeine/reflaxe.rust/tree/main/docs/stdlib-provenance-ledger.json'
  ]) {
    const mutableStdlibLink = JSON.parse(JSON.stringify(releaseComponents))
    mutableStdlibLink.components.find(
      (component) => component.id === 'haxe-standard-library-derived-files'
    ).notice += ` Alternate record: ${externalLink}.`
    expectThrow(
      () => licenseApi.validateRequiredComponentIds(mutableStdlibLink),
      /stdlib release notice must not depend on an external branch URL/
    )
  }
  const stdlibComponent = releaseComponents.components.find(
    (component) => component.id === 'haxe-standard-library-derived-files'
  )
  assert(
    stdlibComponent.notice.includes('provenance/stdlib-provenance-ledger.json'),
    'the stdlib notice must point package reviewers to the archive-local source record'
  )
  assert(
    !stdlibComponent.notice.includes('/blob/main/'),
    'release evidence must not depend on a mutable main-branch link'
  )
  for (const unsafeLicenseSource of [
    '../outside-haxe-license.txt',
    '/tmp/outside-haxe-license.txt',
    'C:\\outside-haxe-license.txt',
    'docs\\licenses\\haxe-stdlib-4.3.7-MIT.txt',
    'docs/licenses/../licenses/haxe-stdlib-4.3.7-MIT.txt'
  ]) {
    expectThrow(
      () => licenseApi.resolveStdlibComponent(stdlibComponent, {
        upstreamStdVersion: '4.3.7',
        upstreamRepository: 'https://github.com/HaxeFoundation/haxe',
        license: {
          id: 'MIT',
          sourceFile: unsafeLicenseSource,
          sha256: 'a'.repeat(64)
        }
      }),
      /stdlib license sourceFile must be exactly docs\/licenses\/haxe-stdlib-4\.3\.7-MIT\.txt/
    )
  }

  const extraComponent = {
    id: 'unreviewed-primary',
    name: 'Different Product',
    kind: 'application',
    versionSource: 'release',
    license: 'Proprietary',
    licenseText: 'Proprietary fixture license text',
    source: 'https://example.invalid/different-product'
  }
  for (const reordered of [
    [extraComponent, ...releaseComponents.components],
    [...releaseComponents.components, extraComponent],
    [...releaseComponents.components].reverse()
  ]) {
    const source = { ...releaseComponents, components: reordered }
    const reorderedSbom = JSON.parse(licenseApi.buildArtifacts('9.9.9', source).get('release-sbom.json'))
    assert.strictEqual(reorderedSbom.metadata.component.name, 'reflaxe.rust')
    assert.strictEqual(reorderedSbom.metadata.component.type, 'application')
    assert.strictEqual(reorderedSbom.metadata.component['bom-ref'], 'pkg:generic/reflaxe-rust@9.9.9')
    assert.strictEqual(reorderedSbom.dependencies[0].ref, 'pkg:generic/reflaxe-rust@9.9.9')
  }
	for (const field of ['licenseSourceFile', 'licenseFile', 'licenseSha256']) {
		const fileBackedExtra = JSON.parse(JSON.stringify(releaseComponents))
		fileBackedExtra.components.push({
			id: `file-backed-extra-${field}`,
			name: `File-backed extra ${field}`,
			kind: 'library',
			version: '1.0.0',
			license: 'MIT',
			licenseText: 'Reviewed inline terms',
			source: 'https://example.invalid/extra',
			[field]: field === 'licenseSha256' ? 'a'.repeat(64) : '.git/config'
		})
		expectThrow(
			() => licenseApi.buildArtifacts('9.9.9', fileBackedExtra),
			/extra release component license text must be inline in the reviewed component record/
		)
	}
	const expectedHaxeLicense = fs
		.readFileSync(path.join(repoRoot, licenseApi.STDLIB_LICENSE_SOURCE_PATH), 'utf8')
		.trim()
	const generatedNotice = licenseApi.buildArtifacts('1.2.34').get('THIRD_PARTY_NOTICES.md')
	assert(
		generatedNotice.includes(
			`${stdlibComponent.notice}\n\n${expectedHaxeLicense}\n\n## Rust crate dependencies`
		),
		'the complete fixed Haxe license bytes must appear in the generated notice'
	)
  const firstSbom = JSON.parse(licenseApi.buildArtifacts('1.2.34').get('release-sbom.json'))
  const secondSbom = JSON.parse(licenseApi.buildArtifacts('12.3.4').get('release-sbom.json'))
  assert(!('serialNumber' in firstSbom), 'deterministic SBOM must omit a fabricated UUID serial number')
  assert.notDeepStrictEqual(firstSbom, secondSbom, 'different package versions must produce different SBOMs')
	const canonicalHaxelib = {
		name: 'reflaxe.rust',
		url: 'https://github.com/fullofcaffeine/reflaxe.rust',
		license: 'GPL-3.0'
	}
	assert.doesNotThrow(() => verifyApi.validateSbomPrimary(firstSbom, canonicalHaxelib, '1.2.34'))
	for (const [label, mutation] of [
		['name', { ...canonicalHaxelib, name: 'different.product' }],
		['missing name', { ...canonicalHaxelib, name: '' }],
		['repository', { ...canonicalHaxelib, url: 'https://example.invalid/different-product' }],
		['missing repository', { ...canonicalHaxelib, url: '' }],
		['empty license', { ...canonicalHaxelib, license: '' }]
	]) {
		expectThrow(
			() => verifyApi.validateSbomPrimary(firstSbom, mutation, '1.2.34'),
			/reviewed reflaxe\.rust Haxelib metadata/,
			`the package verifier must reject a contradictory Haxelib ${label}`
		)
	}
	for (const [label, mutate, pattern] of [
		['name', (sbom) => { sbom.metadata.component.name = 'Different Product' }, /primary component/],
		['kind', (sbom) => { sbom.metadata.component.type = 'library' }, /primary component/],
		['identity', (sbom) => { sbom.metadata.component['bom-ref'] = 'pkg:generic/different@1.2.34' }, /primary component/],
		['license', (sbom) => { sbom.metadata.component.licenses[0].license.id = 'Proprietary' }, /primary component/],
		['repository', (sbom) => { sbom.metadata.component.externalReferences[0].url = 'https://example.invalid' }, /primary component/],
		['root dependency', (sbom) => { sbom.dependencies[0].ref = 'pkg:generic/different@1.2.34' }, /root dependency/]
	]) {
		const mutation = JSON.parse(JSON.stringify(firstSbom))
		mutate(mutation)
		expectThrow(
			() => verifyApi.validateSbomPrimary(mutation, canonicalHaxelib, '1.2.34'),
			pattern,
			`the package verifier must reject a false SBOM ${label}`
		)
	}
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
    const fakeCargo = path.join(cargoFixture, 'cargo')
    const fakeCargoMarker = path.join(cargoFixture, 'fake-cargo-ran.txt')
    write(cargoFixture, 'cargo', `#!/usr/bin/env bash\nprintf invoked > ${JSON.stringify(fakeCargoMarker)}\nexit 97\n`)
    fs.chmodSync(fakeCargo, 0o755)
    const previousCargoBin = process.env.CARGO_BIN
    const previousPath = process.env.PATH
    process.env.CARGO_BIN = fakeCargo
    process.env.PATH = `${cargoFixture}${path.delimiter}${previousPath}`
    let parsedCargo
    try {
      parsedCargo = licenseApi.cargoRequirements(path.join(cargoFixture, 'Cargo.toml'))
    } finally {
      if (previousCargoBin === undefined) delete process.env.CARGO_BIN
      else process.env.CARGO_BIN = previousCargoBin
      process.env.PATH = previousPath
    }
    assert(!fs.existsSync(fakeCargoMarker), 'release evidence must derive Cargo requirements from reviewed manifest bytes without executing ambient Cargo')
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

    const reviewedSource = path.join(temp, 'reviewed-source')
    fs.cpSync(left, reviewedSource, { recursive: true })
    write(
      reviewedSource,
      'docs/stdlib-provenance-ledger.json',
      fs.readFileSync(path.join(left, 'provenance', 'stdlib-provenance-ledger.json'))
    )

    const verifyArtifact = (options, canonicalZipPath = rightZip) =>
      verifyApi.verifyReleaseArtifact({
        ...options,
        canonicalZipPath,
        stdlibLedgerSourcePath:
          options.stdlibLedgerSourcePath ||
          path.join(options.sourceRoot || left, 'provenance', 'stdlib-provenance-ledger.json')
      })

    const result = verifyApi.verifyReleaseArtifact({
      zipPath: leftZip,
      canonicalZipPath: rightZip,
      version: VERSION,
      tag: TAG,
      sourceCommit: SOURCE_SHA,
      sourceRoot: reviewedSource
    })
    assert.strictEqual(result.sha256, sha256(leftZip))
    assert.strictEqual(result.size, fs.statSync(leftZip).size)
    assert(result.entries.includes('release-metadata.json'))
    assert(result.entries.includes('release-sbom.json'))
    assert(result.entries.includes('THIRD_PARTY_NOTICES.md'))
    assert(result.entries.includes('vendor/reflaxe/LICENSE'))
    assert(result.entries.includes('vendor/reflaxe/provenance.json'))
    assert(result.entries.includes('vendor/reflaxe/reflaxe-rust.patch'))
    assert(result.entries.includes('provenance/stdlib-provenance-ledger.json'))
    assert(
      fs
        .readFileSync(path.join(left, 'THIRD_PARTY_NOTICES.md'), 'utf8')
        .includes('provenance/stdlib-provenance-ledger.json'),
      'the generated notice must name the package-local stdlib source record'
    )
    assert.deepStrictEqual(
      [...result.entries].sort(zipApi.compareEntryNames),
      result.entries,
      'archive entries must be sorted'
    )
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: leftZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: left
        }),
      /an independently rebuilt canonical package is required/
    )
    expectThrow(
      () =>
        verifyArtifact(
          {
            zipPath: leftZip,
            version: VERSION,
            tag: TAG,
            sourceCommit: SOURCE_SHA,
            sourceRoot: left
          },
          leftZip
        ),
      /candidate and canonical package must be separate independently built files/
    )

    const missingRoot = path.join(temp, 'missing-root')
    packageFixture(missingRoot)
    fs.rmSync(path.join(missingRoot, 'runtime'), { recursive: true })
    const missingZip = path.join(temp, 'missing.zip')
    zipApi.createDeterministicZip(missingRoot, missingZip)
    expectThrow(
      () =>
        verifyArtifact({
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
        verifyArtifact({
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
        verifyArtifact({
          zipPath: badPatchZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: badPatchRoot
        }),
      /vendored Reflaxe patch digest does not match/
    )

    const badLicenseRoot = path.join(temp, 'bad-license')
    packageFixture(badLicenseRoot)
    write(badLicenseRoot, 'vendor/reflaxe/LICENSE', 'MIT License\nforged package bytes\n')
    const badLicenseLeftZip = path.join(temp, 'bad-license-left.zip')
    const badLicenseRightZip = path.join(temp, 'bad-license-right.zip')
    zipApi.createDeterministicZip(badLicenseRoot, badLicenseLeftZip)
    zipApi.createDeterministicZip(badLicenseRoot, badLicenseRightZip)
    expectThrow(
      () =>
        verifyArtifact(
          {
            zipPath: badLicenseLeftZip,
            version: VERSION,
            tag: TAG,
            sourceCommit: SOURCE_SHA,
            sourceRoot: badLicenseRoot
          },
          badLicenseRightZip
        ),
      /vendored Reflaxe license digest does not match its provenance record/
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
        verifyArtifact({
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
        verifyArtifact({
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
        verifyArtifact({
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
        verifyArtifact({
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
        verifyArtifact({
          zipPath: badMetadataZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: metadataSourceRoot
        }),
      /reviewed reflaxe\.rust Haxelib metadata license must be a non-empty string/
    )

		for (const [name, mutate] of [
			['contradictory-project-name', (haxelib) => { haxelib.name = 'different.product' }],
			['missing-project-name', (haxelib) => { haxelib.name = '' }],
			['contradictory-project-url', (haxelib) => { haxelib.url = 'https://example.invalid/different-product' }],
			['missing-project-url', (haxelib) => { haxelib.url = '' }],
			['missing-project-license', (haxelib) => { haxelib.license = '' }]
		]) {
			const contradictoryRoot = path.join(temp, name)
			packageFixture(contradictoryRoot)
			const haxelibPath = path.join(contradictoryRoot, 'haxelib.json')
			const haxelib = JSON.parse(fs.readFileSync(haxelibPath, 'utf8'))
			mutate(haxelib)
			writeJson(contradictoryRoot, 'haxelib.json', haxelib)
			const canonicalRoot = path.join(temp, `${name}-canonical`)
			fs.cpSync(contradictoryRoot, canonicalRoot, { recursive: true })
			const candidateZip = path.join(temp, `${name}.zip`)
			const canonicalZip = path.join(temp, `${name}-canonical.zip`)
			zipApi.createDeterministicZip(contradictoryRoot, candidateZip)
			zipApi.createDeterministicZip(canonicalRoot, canonicalZip)
			expectThrow(
				() => verifyArtifact({
					zipPath: candidateZip,
					version: VERSION,
					tag: TAG,
					sourceCommit: SOURCE_SHA,
					sourceRoot: contradictoryRoot
				}, canonicalZip),
				/reviewed reflaxe\.rust Haxelib metadata/
			)
		}

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
        verifyArtifact({
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
        verifyArtifact({
          zipPath: badNoticeZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: badNoticeRoot
        }),
      /archive entry differs from generated license evidence: THIRD_PARTY_NOTICES\.md/
    )

    const expectCanonicalMismatch = (name, relativePath, content) => {
      const candidateRoot = path.join(temp, name)
      fs.cpSync(left, candidateRoot, { recursive: true })
      write(candidateRoot, relativePath, content)
      const candidateZip = path.join(temp, `${name}.zip`)
      zipApi.createDeterministicZip(candidateRoot, candidateZip)
      expectThrow(
        () =>
          verifyArtifact({
            zipPath: candidateZip,
            version: VERSION,
            tag: TAG,
            sourceCommit: SOURCE_SHA,
            sourceRoot: left
          }),
        /optional archive entry does not match reviewed source presence|archive entry differs from the reviewed source|release artifact differs from the independently rebuilt canonical package/
      )
    }

    expectCanonicalMismatch('unexpected-run-hx', 'Run.hx', 'unreviewed runner\n')
    expectCanonicalMismatch('unexpected-run-n', 'run.n', 'unreviewed bytecode\n')
    expectCanonicalMismatch('changed-readme', 'README.md', '# unreviewed readme\n')
    expectCanonicalMismatch('changed-extra-params', 'extraParams.hxml', '# unreviewed flags\n')
    expectCanonicalMismatch('unexpected-source', 'src/unreviewed/Payload.hx', 'package unreviewed;\n')
    expectCanonicalMismatch('unexpected-runtime', 'runtime/unreviewed/payload.txt', 'unreviewed runtime\n')
    expectCanonicalMismatch('unexpected-vendor', 'vendor/other/payload.txt', 'unreviewed vendor\n')

    for (const [name, field, value] of [
      ['contradictory-reflaxe-license', 'license', 'Apache-2.0'],
      ['contradictory-reflaxe-url', 'url', 'https://example.invalid/reflaxe']
    ]) {
      const contradictoryRoot = path.join(temp, name)
      fs.cpSync(left, contradictoryRoot, { recursive: true })
      const nestedPath = path.join(contradictoryRoot, 'vendor', 'reflaxe', 'haxelib.json')
      const nested = JSON.parse(fs.readFileSync(nestedPath, 'utf8'))
      nested[field] = value
      writeJson(contradictoryRoot, 'vendor/reflaxe/haxelib.json', nested)
      const contradictoryCanonicalRoot = path.join(temp, `${name}-canonical`)
      fs.cpSync(contradictoryRoot, contradictoryCanonicalRoot, { recursive: true })
      const contradictoryZip = path.join(temp, `${name}.zip`)
      const contradictoryCanonicalZip = path.join(temp, `${name}-canonical.zip`)
      zipApi.createDeterministicZip(contradictoryRoot, contradictoryZip)
      zipApi.createDeterministicZip(contradictoryCanonicalRoot, contradictoryCanonicalZip)
      expectThrow(
        () =>
          verifyArtifact(
            {
              zipPath: contradictoryZip,
              version: VERSION,
              tag: TAG,
              sourceCommit: SOURCE_SHA,
              sourceRoot: contradictoryRoot
            },
            contradictoryCanonicalZip
          ),
        /Reflaxe haxelib metadata contradicts provenance/
      )
    }

    for (const [name, mutate, pattern] of [
      [
        'renamed-reflaxe-component',
        (provenance) => {
          provenance.component.name = 'Different framework'
        },
        /Reflaxe provenance component name must be Reflaxe/
      ],
      [
        'missing-reflaxe-license',
        (provenance, nested) => {
          delete provenance.component.license
          delete nested.license
        },
        /Reflaxe provenance license must be a non-empty string/
      ],
      [
        'missing-reflaxe-repository',
        (provenance, nested) => {
          delete provenance.component.upstreamRepository
          delete nested.url
        },
        /Reflaxe provenance repository must be a non-empty string/
      ]
    ]) {
      const invalidRoot = path.join(temp, name)
      fs.cpSync(left, invalidRoot, { recursive: true })
      const provenance = JSON.parse(
        fs.readFileSync(path.join(invalidRoot, 'vendor', 'reflaxe', 'provenance.json'), 'utf8')
      )
      const nested = JSON.parse(
        fs.readFileSync(path.join(invalidRoot, 'vendor', 'reflaxe', 'haxelib.json'), 'utf8')
      )
      mutate(provenance, nested)
      writeJson(invalidRoot, 'vendor/reflaxe/provenance.json', provenance)
      writeJson(invalidRoot, 'vendor/reflaxe/haxelib.json', nested)
      const invalidCanonicalRoot = path.join(temp, `${name}-canonical`)
      fs.cpSync(invalidRoot, invalidCanonicalRoot, { recursive: true })
      const invalidZip = path.join(temp, `${name}.zip`)
      const invalidCanonicalZip = path.join(temp, `${name}-canonical.zip`)
      zipApi.createDeterministicZip(invalidRoot, invalidZip)
      zipApi.createDeterministicZip(invalidCanonicalRoot, invalidCanonicalZip)
      expectThrow(
        () =>
          verifyArtifact(
            {
              zipPath: invalidZip,
              version: VERSION,
              tag: TAG,
              sourceCommit: SOURCE_SHA,
              sourceRoot: invalidRoot
            },
            invalidCanonicalZip
          ),
        pattern
      )
    }

    const missingLedgerRoot = path.join(temp, 'missing-ledger')
    fs.cpSync(left, missingLedgerRoot, { recursive: true })
    fs.rmSync(path.join(missingLedgerRoot, 'provenance', 'stdlib-provenance-ledger.json'))
    const missingLedgerZip = path.join(temp, 'missing-ledger.zip')
    zipApi.createDeterministicZip(missingLedgerRoot, missingLedgerZip)
    expectThrow(
      () =>
        verifyArtifact({
          zipPath: missingLedgerZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: left
        }),
      /required archive entry is missing: provenance\/stdlib-provenance-ledger\.json/
    )

    expectCanonicalMismatch(
      'changed-ledger',
      'provenance/stdlib-provenance-ledger.json',
      '{"schemaVersion":1,"forged":true}\n'
    )

    const wrongLedgerSource = path.join(temp, 'wrong-ledger-source')
    fs.cpSync(reviewedSource, wrongLedgerSource, { recursive: true })
    write(
      wrongLedgerSource,
      'docs/stdlib-provenance-ledger.json',
      '{"schemaVersion":1,"forgedSource":true}\n'
    )
    expectThrow(
      () =>
        verifyApi.verifyReleaseArtifact({
          zipPath: leftZip,
          canonicalZipPath: rightZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA,
          sourceRoot: wrongLedgerSource
        }),
      /archive entry differs from the reviewed source: provenance\/stdlib-provenance-ledger\.json/
    )

    const optionalLeft = path.join(temp, 'optional-left')
    const optionalRight = path.join(temp, 'optional-right')
    packageFixture(optionalLeft)
    packageFixture(optionalRight)
    for (const root of [optionalLeft, optionalRight]) {
      write(root, 'Run.hx', 'class Run {}\n')
      write(root, 'run.n', 'reviewed bytecode fixture\n')
    }
    const optionalLeftZip = path.join(temp, 'optional-left.zip')
    const optionalRightZip = path.join(temp, 'optional-right.zip')
    zipApi.createDeterministicZip(optionalLeft, optionalLeftZip)
    zipApi.createDeterministicZip(optionalRight, optionalRightZip)
    verifyArtifact(
      {
        zipPath: optionalLeftZip,
        version: VERSION,
        tag: TAG,
        sourceCommit: SOURCE_SHA,
        sourceRoot: optionalLeft
      },
      optionalRightZip
    )

    const unsafeZip = path.join(temp, 'unsafe.zip')
    fs.writeFileSync(
      unsafeZip,
      Buffer.from(zipSync({ '../escape.txt': strToU8('escape'), 'haxelib.json': strToU8('{}') }))
    )
    expectThrow(
      () =>
        verifyArtifact({
          zipPath: unsafeZip,
          version: VERSION,
          tag: TAG,
          sourceCommit: SOURCE_SHA
        }),
      /unsafe archive entry/
    )

		const gitMetadataLeft = path.join(temp, 'git-metadata-left')
		const gitMetadataRight = path.join(temp, 'git-metadata-right')
		packageFixture(gitMetadataLeft)
		packageFixture(gitMetadataRight)
		write(gitMetadataLeft, 'runtime/.git', 'gitdir: external\n')
		write(gitMetadataRight, 'runtime/.git', 'gitdir: external\n')
		const gitMetadataLeftZip = path.join(temp, 'git-metadata-left.zip')
		const gitMetadataRightZip = path.join(temp, 'git-metadata-right.zip')
		zipApi.createDeterministicZip(gitMetadataLeft, gitMetadataLeftZip)
		zipApi.createDeterministicZip(gitMetadataRight, gitMetadataRightZip)
		expectThrow(
			() => verifyArtifact({
				zipPath: gitMetadataLeftZip,
				version: VERSION,
				tag: TAG,
				sourceCommit: SOURCE_SHA,
				sourceRoot: gitMetadataLeft
			}, gitMetadataRightZip),
			/development-only archive entry is not allowed: runtime\/\.git/
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
