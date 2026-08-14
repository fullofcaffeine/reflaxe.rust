#!/usr/bin/env node

const assert = require('node:assert/strict')
const crypto = require('node:crypto')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const net = require('node:net')
const { spawn, spawnSync } = require('node:child_process')
const test = require('node:test')

const repoRoot = path.resolve(__dirname, '..', '..')
const fixtureRoot = path.join(repoRoot, 'test', 'contract', 'contained_unsafe_boundary_red_state')
const copiedOutput = path.join(fixtureRoot, 'out_test_copied')
const ambientOutput = path.join(fixtureRoot, 'out_test_ambient')
const defaultHaxe = path.join(
  repoRoot,
  'node_modules',
  '.bin',
  process.platform === 'win32' ? 'haxe.cmd' : 'haxe'
)
const haxe = process.env.HAXE_BIN || defaultHaxe
const haxeServer = process.env.HAXE_SERVER_BIN || haxe

function compile(hxml, outputName) {
  return spawnSync(haxe, [hxml, '-D', `rust_output=${outputName}`], {
    cwd: fixtureRoot,
    encoding: 'utf8',
    env: process.env
  })
}

function transcript(result) {
  return `${result.stdout || ''}${result.stderr || ''}`
}

function snapshotTree(root, normalizeGeneratedManifest = false) {
  const entries = []
  const visit = (absolute, relative) => {
    const stat = fs.lstatSync(absolute)
    const identity = { path: relative, mode: stat.mode, size: stat.size }
    if (stat.isDirectory()) {
      entries.push({ ...identity, kind: 'directory' })
      for (const name of fs.readdirSync(absolute).sort()) {
        visit(path.join(absolute, name), relative === '' ? name : `${relative}/${name}`)
      }
    } else if (stat.isFile()) {
      let bytes = fs.readFileSync(absolute)
      if (normalizeGeneratedManifest && relative === '_GeneratedFiles.json') {
        const manifest = JSON.parse(bytes.toString('utf8'))
        delete manifest.id
        delete manifest.wasCached
        bytes = Buffer.from(JSON.stringify(manifest))
      }
      const sha256 = crypto.createHash('sha256').update(bytes).digest('hex')
      entries.push({ ...identity, size: bytes.length, kind: 'file', sha256 })
    } else if (stat.isSymbolicLink()) {
      entries.push({ ...identity, kind: 'symlink', target: fs.readlinkSync(absolute) })
    } else {
      entries.push({ ...identity, kind: 'other' })
    }
  }
  visit(root, '')
  return entries
}

async function unusedLoopbackPort() {
  const server = net.createServer()
  await new Promise((resolve, reject) => {
    server.once('error', reject)
    server.listen(0, '127.0.0.1', resolve)
  })
  const address = server.address()
  assert.notEqual(address, null)
  const port = address.port
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  return port
}

async function waitForCompilerServer(port, compilerProcess) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const probe = spawnSync(haxe, ['--connect', String(port), '-version'], {
      cwd: repoRoot,
      encoding: 'utf8',
      env: process.env
    })
    if (probe.status === 0) return
    if (compilerProcess.exitCode !== null) {
      throw new Error(`Haxe compiler server exited early with status ${compilerProcess.exitCode}`)
    }
    await new Promise(resolve => setTimeout(resolve, 25))
  }
  throw new Error('Haxe compiler server did not become ready')
}

function compileThroughServer(port, fixtureRoot, reserved) {
  const args = ['--connect', String(port), 'compile.hxml']
  if (reserved) args.push('-D', 'support_crate_reserved')
  return spawnSync(haxe, args, {
    cwd: fixtureRoot,
    encoding: 'utf8',
    env: process.env
  })
}

function compileAdmittedSourceThroughServer(port, callerRoot, sourceRoot, shadowRoot) {
  return spawnSync(haxe, [
    '--connect', String(port),
    '-cp', shadowRoot,
    '-cp', sourceRoot,
    '-lib', 'reflaxe.rust',
    '-D', 'reflaxe_rust_profile=metal',
    '-D', 'rust_no_build',
    '-D', `rust_output=${path.join(callerRoot, 'out')}`,
    '-main', 'supportcrateadmitted.Main'
  ], {
    cwd: callerRoot,
    encoding: 'utf8',
    env: process.env
  })
}

function compileNegativeFixture(fixture) {
  return spawnSync(haxe, ['compile.hxml'], {
    cwd: path.join(repoRoot, 'test', 'negative', fixture),
    encoding: 'utf8',
    env: process.env
  })
}

function compilePositiveFixture(fixture) {
  return spawnSync(haxe, ['compile.hxml'], {
    cwd: path.join(repoRoot, 'test', 'positive', fixture),
    encoding: 'utf8',
    env: process.env
  })
}

function compileSupportCrateSource(source, extraArgs = []) {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-support-crate-plan-'))
  const output = path.join(fixtureRoot, 'out')
  fs.writeFileSync(path.join(fixtureRoot, 'Main.hx'), source)
  const result = spawnSync(haxe, [
    '-cp', fixtureRoot,
    '-lib', 'reflaxe.rust',
    '-D', 'reflaxe_rust_profile=metal',
    '-D', 'rust_no_build',
    '-D', `rust_output=${output}`,
    ...extraArgs,
    '-main', 'Main'
  ], {
    cwd: repoRoot,
    encoding: 'utf8',
    env: process.env
  })
  result.outputExists = fs.existsSync(output)
  fs.rmSync(fixtureRoot, { recursive: true, force: true })
  return result
}

function supportCrateSource(overrides = '') {
  return `
@:rustSupportCrate({
  name: "native_page_size_support",
  sourceRoot: "native/native_page_size_support",
  unsafePolicy: "audited",
  targets: ["*"],
  dependencies: []${overrides}
})
@:native("native_page_size_support::PageSize")
extern class PageSize {
  public static function current():Int;
}

class Main {
  static function main():Void {
    PageSize.current();
  }
}
`
}

function admittedSourceManifest() {
  return `[package]
name = "sample_support"
version = "0.0.0"
edition = "2021"
publish = false

[lib]
path = "src/lib.rs"

[dependencies]
`
}

function compileAdmittedSourceFixture(mutate) {
  const cacheRoot = path.join(repoRoot, '.cache')
  fs.mkdirSync(cacheRoot, { recursive: true })
  const fixtureRoot = fs.mkdtempSync(path.join(cacheRoot, 'support-crate-admission-'))
  const crateRoot = path.join(fixtureRoot, 'native', 'sample_support')
  const output = path.join(fixtureRoot, 'out')
  fs.mkdirSync(path.join(crateRoot, 'src'), { recursive: true })
  fs.writeFileSync(path.join(fixtureRoot, 'Main.hx'), `
@:rustSupportCrate({
  name: "sample_support",
  sourceRoot: "native/sample_support",
  unsafePolicy: "forbid",
  targets: ["*"],
  dependencies: []
})
@:native("sample_support::Api")
extern class SampleSupportApi {
  public static function answer():Int;
}
class Main { static function main():Void { SampleSupportApi.answer(); } }
`)
  fs.writeFileSync(path.join(crateRoot, 'Cargo.toml'), admittedSourceManifest())
  fs.writeFileSync(path.join(crateRoot, 'src', 'lib.rs'), 'pub fn answer() -> i32 { 42 }\n')
  mutate(crateRoot)
  const result = spawnSync(haxe, [
    '-lib', 'reflaxe.rust',
    '-D', 'reflaxe_rust_profile=metal',
    '-D', 'rust_no_build',
    '-D', `rust_output=${output}`,
    '-main', 'Main'
  ], {
    cwd: fixtureRoot,
    encoding: 'utf8',
    env: process.env
  })
  result.outputExists = fs.existsSync(output)
  fs.rmSync(fixtureRoot, { recursive: true, force: true })
  return result
}

test('current facilities cannot own a separate contained-unsafe support crate', () => {
  fs.rmSync(copiedOutput, { recursive: true, force: true })
  fs.rmSync(ambientOutput, { recursive: true, force: true })

  try {
    const copied = compile('compile.hxml', 'out_test_copied')
    assert.ifError(copied.error)
    assert.notEqual(copied.status, 0, 'copied unsafe source must fail')
    assert.match(transcript(copied), /usage of an `unsafe` block/)
    assert.match(transcript(copied), /HXRS-CARGO-INVOCATION/)

    const copiedMain = fs.readFileSync(path.join(copiedOutput, 'src', 'main.rs'), 'utf8')
    const copiedHelper = fs.readFileSync(path.join(copiedOutput, 'src', 'unsafe_probe.rs'), 'utf8')
    assert.match(copiedMain, /#!\[forbid\(unsafe_code\)\]/)
    assert.match(copiedHelper, /unsafe \{ std::ptr::read_volatile\(&value\) \}/)

    const ambient = compile('compile.ambient-path.hxml', 'out_test_ambient')
    assert.ifError(ambient.error)
    assert.equal(ambient.status, 0, transcript(ambient))

    const ambientManifest = fs.readFileSync(path.join(ambientOutput, 'Cargo.toml'), 'utf8')
    const ambientMain = fs.readFileSync(path.join(ambientOutput, 'src', 'main.rs'), 'utf8')
    assert.match(ambientManifest, /unsafe_support = \{ path = "\.\.\/support" \}/)
    assert.match(ambientMain, /#!\[forbid\(unsafe_code\)\]/)
    assert.equal(fs.existsSync(path.join(ambientOutput, 'src', 'unsafe_probe.rs')), false)
    assert.equal(fs.existsSync(path.join(ambientOutput, 'support-crates')), false)
  } finally {
    fs.rmSync(copiedOutput, { recursive: true, force: true })
    fs.rmSync(ambientOutput, { recursive: true, force: true })
  }
})

test('a valid support-crate declaration reaches only the unavailable source-admission boundary', () => {
  const result = compileSupportCrateSource(supportCrateSource())
  assert.ifError(result.error)
  assert.notEqual(result.status, 0, 'source admission is not implemented in Stage 2A')
  assert.match(transcript(result), /\[HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE\]/)
  assert.equal(result.outputExists, false, 'Stage 2A must fail before it creates generated output')
})

test('support-crate metadata uses a closed compile-time grammar', () => {
  const cases = [
    {
      name: 'missing required field',
      source: supportCrateSource().replace('  dependencies: []\n', ''),
      expected: /\[HXRS-METADATA-VALUE\].*missing required field `dependencies`/
    },
    {
      name: 'unknown field',
      source: supportCrateSource(',\n  command: "cargo build"'),
      expected: /\[HXRS-METADATA-VALUE\].*unknown field `command`/
    },
    {
      name: 'duplicate field',
      source: supportCrateSource(',\n  name: "other_support"'),
      expected: /\[HXRS-METADATA-VALUE\].*duplicate field `name`/
    },
    {
      name: 'parent traversal',
      source: supportCrateSource().replace('native/native_page_size_support', '../native_page_size_support'),
      expected: /\[HXRS-METADATA-VALUE\].*sourceRoot/
    },
    {
      name: 'reserved Rust crate identifier',
      source: supportCrateSource()
        .replaceAll('native_page_size_support', 'crate'),
      expected: /\[HXRS-METADATA-VALUE\].*lowercase Rust identifier/
    },
    ...['std', 'core', 'alloc'].map(name => ({
      name: `backend-reserved crate root ${name}`,
      source: supportCrateSource().replaceAll('native_page_size_support', name),
      expected: /\[HXRS-METADATA-VALUE\].*lowercase Rust identifier/
    })),
    {
      name: 'Cargo-reserved package name test',
      source: supportCrateSource().replaceAll('native_page_size_support', 'test'),
      expected: /\[HXRS-METADATA-VALUE\].*lowercase Rust identifier/
    },
    {
      name: 'crate name longer than Cargo permits',
      source: supportCrateSource().replaceAll('native_page_size_support', `x${'a'.repeat(64)}`),
      expected: /\[HXRS-METADATA-VALUE\].*lowercase Rust identifier/
    },
    {
      name: 'crate path mismatch',
      source: supportCrateSource().replace('native_page_size_support::PageSize', 'other_crate::PageSize'),
      expected: /\[HXRS-METADATA-VALUE\].*`@:native`.*native_page_size_support/
    },
    {
      name: 'invalid unsafe policy',
      source: supportCrateSource().replace('unsafePolicy: "audited"', 'unsafePolicy: "allow"'),
      expected: /\[HXRS-METADATA-VALUE\].*unsafePolicy.*forbid.*audited/
    },
    {
      name: 'target-specific declaration without rust_target',
      source: supportCrateSource().replace('targets: ["*"]', 'targets: ["aarch64-apple-darwin"]'),
      expected: /\[HXRS-METADATA-VALUE\].*requires `-D rust_target=/
    },
    {
      name: 'version range',
      source: supportCrateSource().replace('dependencies: []', 'dependencies: [{name: "libc", version: "^0.2", defaultFeatures: false, features: []}]'),
      expected: /\[HXRS-METADATA-VALUE\].*exact registry version/
    },
    {
      name: 'non-canonical exact version',
      source: supportCrateSource().replace('dependencies: []', 'dependencies: [{name: "libc", version: "=01.2.3", defaultFeatures: false, features: []}]'),
      expected: /\[HXRS-METADATA-VALUE\].*exact registry version/
    },
    {
      name: 'exact version component larger than Cargo SemVer permits',
      source: supportCrateSource().replace('dependencies: []', 'dependencies: [{name: "libc", version: "=18446744073709551616.0.0", defaultFeatures: false, features: []}]'),
      expected: /\[HXRS-METADATA-VALUE\].*exact registry version/
    },
    {
      name: 'self dependency',
      source: supportCrateSource().replace('dependencies: []', 'dependencies: [{name: "native_page_size_support", version: "=1.0.0", defaultFeatures: false, features: []}]'),
      expected: /\[HXRS-METADATA-VALUE\].*cannot depend on itself/
    }
  ]

  for (const fixture of cases) {
    const result = compileSupportCrateSource(fixture.source)
    assert.ifError(result.error)
    assert.notEqual(result.status, 0, `${fixture.name} unexpectedly compiled`)
    assert.match(transcript(result), fixture.expected, fixture.name)
  }
})

test('normalization makes equivalent repeated declarations equal', () => {
  const declaration = supportCrateSource().replace(/\nclass Main[\s\S]*$/, '')
  const first = declaration
    .replace('targets: ["*"]', 'targets: ["x86_64-apple-darwin", "aarch64-apple-darwin"]')
    .replace('dependencies: []', 'dependencies: [{name: "serde", version: "=1.0.0", defaultFeatures: false, features: []}, {name: "libc", version: "=0.2.180", defaultFeatures: false, features: ["std", "alloc"]}]')
  const second = declaration
    .replace('extern class PageSize', 'extern class PageSizeAgain')
    .replace('::PageSize")', '::PageSizeAgain")')
    .replace('targets: ["*"]', 'targets: ["aarch64-apple-darwin", "x86_64-apple-darwin"]')
    .replace('dependencies: []', 'dependencies: [{name: "libc", version: "=0.2.180", defaultFeatures: false, features: ["alloc", "std"]}, {name: "serde", version: "=1.0.0", defaultFeatures: false, features: []}]')
  const source = `${first}\n${second}\nclass Main { static function main():Void {} }\n`
  const result = compileSupportCrateSource(source, ['-D', 'rust_target=x86_64-apple-darwin'])
  assert.ifError(result.error)
  assert.notEqual(result.status, 0, 'source admission is not implemented in Stage 2A')
  assert.match(transcript(result), /\[HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE\]/)
})

test('a valid two-part Cargo target name is preserved exactly', () => {
  const source = supportCrateSource().replace('targets: ["*"]', 'targets: ["wasm32-wasip1"]')
  const result = compileSupportCrateSource(source, ['-D', 'rust_target=wasm32-wasip1'])
  assert.ifError(result.error)
  assert.notEqual(result.status, 0, 'source admission is not implemented in Stage 2A')
  assert.match(transcript(result), /\[HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE\]/)
})

test('a valid Cargo target name can contain a dotted architecture segment', () => {
  const target = 'thumbv8m.main-none-eabi'
  const source = supportCrateSource().replace('targets: ["*"]', `targets: ["${target}"]`)
  const result = compileSupportCrateSource(source, ['-D', `rust_target=${target}`])
  assert.ifError(result.error)
  assert.notEqual(result.status, 0, 'source admission is not implemented in Stage 2A')
  assert.match(transcript(result), /\[HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE\]/)
})

test('the Stage 2A planner cannot read the filesystem', () => {
  const source = fs.readFileSync(path.join(repoRoot, 'src', 'reflaxe', 'rust', 'SupportCrateRequestPlanner.hx'), 'utf8')
  assert.doesNotMatch(source, /sys\.FileSystem|sys\.io\.File|Context\.resolvePath|Context\.getClassPath/)
})

test('support-crate metadata inside an inline record field is rejected', () => {
  const result = compileNegativeFixture('support_crate_reserved_inline_record_field_metadata')
  assert.ifError(result.error)
  assert.notEqual(result.status, 0, 'inline record field metadata unexpectedly compiled')
  assert.match(transcript(result), /\[HXRS-METADATA-PLACEMENT\].*only on an extern class/)
})

test('support-crate metadata on type parameters and function arguments is rejected', () => {
  for (const fixture of [
    'support_crate_reserved_type_parameter_metadata',
    'support_crate_reserved_recursive_type_parameter_metadata',
    'support_crate_reserved_local_type_parameter_metadata',
    'support_crate_reserved_local_record_type_metadata',
    'support_crate_reserved_expression_record_type_metadata',
    'support_crate_reserved_class_init_metadata',
    'support_crate_reserved_overload_type_parameter_metadata',
    'support_crate_reserved_argument_metadata'
  ]) {
    const result = compileNegativeFixture(fixture)
    assert.ifError(result.error)
    assert.notEqual(result.status, 0, `${fixture} unexpectedly compiled`)
    assert.match(transcript(result), /\[HXRS-METADATA-PLACEMENT\].*only on an extern class/)
  }
})

test('a repeated declaration must be exactly equal after normalization', () => {
  const declaration = supportCrateSource().replace(/\nclass Main[\s\S]*$/, '')
  const second = declaration
    .replace('extern class PageSize', 'extern class PageSizeAgain')
    .replace('::PageSize")', '::PageSizeAgain")')
    .replace('sourceRoot: "native/native_page_size_support"', 'sourceRoot: "native/other_support"')
  const source = `${declaration}\n${second}\nclass Main { static function main():Void {} }\n`
  const result = compileSupportCrateSource(source)
  assert.ifError(result.error)
  assert.notEqual(result.status, 0, 'conflicting declarations unexpectedly merged')
  assert.match(transcript(result), /\[HXRS-METADATA-VALUE\].*Conflicting `@:rustSupportCrate` declaration/)
})

test('a complete source bundle reaches the Stage 3 emission stop on macOS arm64', { skip: process.platform !== 'darwin' || process.arch !== 'arm64' }, () => {
  const fixtureRoot = path.join(repoRoot, 'test', 'contract', 'support_crate_admitted_source')
  const output = path.join(fixtureRoot, 'out')
  fs.rmSync(output, { recursive: true, force: true })
  try {
    const result = spawnSync(haxe, ['compile.hxml'], {
      cwd: fixtureRoot,
      encoding: 'utf8',
      env: process.env
    })
    assert.ifError(result.error)
    assert.notEqual(result.status, 0, 'Stage 3 output unexpectedly became enabled')
    assert.match(transcript(result), /\[HXRS-SUPPORT-CRATE-EMISSION-DISABLED\]/)
    assert.doesNotMatch(transcript(result), /\/private\/|\/Users\//,
      'the admission diagnostic leaked a machine-local source path')
    assert.equal(fs.existsSync(output), false, 'admission created Cargo or Rust output')
  } finally {
    fs.rmSync(output, { recursive: true, force: true })
  }
})

test('source admission rejects malformed bundle authority on macOS arm64', { skip: process.platform !== 'darwin' || process.arch !== 'arm64' }, () => {
  const cases = [
    {
      name: 'manifest mismatch',
      mutate: root => fs.appendFileSync(path.join(root, 'Cargo.toml'), '\n[workspace]\n')
    },
    {
      name: 'non-canonical Rust line endings',
      mutate: root => fs.writeFileSync(path.join(root, 'src', 'lib.rs'), 'pub fn answer() -> i32 { 42 }\r\n')
    },
    {
      name: 'forbidden root build script',
      mutate: root => fs.writeFileSync(path.join(root, 'build.rs'), 'fn main() {}\n')
    },
    {
      name: 'empty source directory',
      mutate: root => fs.mkdirSync(path.join(root, 'src', 'empty'))
    },
    {
      name: 'hard-linked source file',
      mutate: root => fs.linkSync(path.join(root, 'src', 'lib.rs'), path.join(root, 'src', 'alias.rs'))
    }
  ]

  for (const fixture of cases) {
    const result = compileAdmittedSourceFixture(fixture.mutate)
    assert.ifError(result.error)
    assert.notEqual(result.status, 0, `${fixture.name} unexpectedly compiled`)
    assert.match(transcript(result), /\[HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE\]/, fixture.name)
    assert.doesNotMatch(transcript(result), /\/private\/|\/Users\//,
      `${fixture.name} leaked a machine-local source path`)
    assert.equal(result.outputExists, false, `${fixture.name} created Cargo or Rust output`)
  }
})

test('support-crate request planning stays isolated through a warm compiler server', async () => {
  const port = await unusedLoopbackPort()
  const fixtureRoot = path.join(repoRoot, 'test', 'contract', 'support_crate_warm_lifecycle')
  const output = path.join(fixtureRoot, 'out')
  const compilerServer = spawn(haxeServer, ['--wait', String(port)], {
    cwd: repoRoot,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: process.env
  })

  try {
    await waitForCompilerServer(port, compilerServer)

    const safeFirst = compileThroughServer(port, fixtureRoot, false)
    assert.ifError(safeFirst.error)
    assert.equal(safeFirst.status, 0, transcript(safeFirst))
    const safeTree = snapshotTree(output)
    const stableSafeTree = snapshotTree(output, true)
    const safeMain = fs.readFileSync(path.join(output, 'src', 'main.rs'))

    const reservedFirst = compileThroughServer(port, fixtureRoot, true)
    assert.ifError(reservedFirst.error)
    assert.notEqual(reservedFirst.status, 0, 'reserved metadata unexpectedly compiled through the warm server')
    assert.match(transcript(reservedFirst), /\[HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE\]/)
    assert.deepEqual(snapshotTree(output), safeTree,
      'the first rejected warm request changed the accepted output tree')

    const safeSecond = compileThroughServer(port, fixtureRoot, false)
    assert.ifError(safeSecond.error)
    assert.equal(safeSecond.status, 0, transcript(safeSecond))
    assert.deepEqual(fs.readFileSync(path.join(output, 'src', 'main.rs')), safeMain,
      'the second safe compile changed generated main.rs')
    const safeSecondTree = snapshotTree(output)
    assert.deepEqual(snapshotTree(output, true), stableSafeTree,
      'the safe warm compile changed the complete generated output tree')

    const reservedSecond = compileThroughServer(port, fixtureRoot, true)
    assert.ifError(reservedSecond.error)
    assert.notEqual(reservedSecond.status, 0, 'the repeated reserved request unexpectedly compiled')
    assert.match(transcript(reservedSecond), /\[HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE\]/)
    assert.deepEqual(snapshotTree(output), safeSecondTree,
      'the repeated rejected warm request changed the accepted output tree')
  } finally {
    fs.rmSync(output, { recursive: true, force: true })
    compilerServer.kill('SIGTERM')
    await new Promise(resolve => {
      if (compilerServer.exitCode !== null) return resolve()
      compilerServer.once('exit', resolve)
      setTimeout(() => {
        compilerServer.kill('SIGKILL')
        resolve()
      }, 2000).unref()
    })
  }
})

test('the warm compiler keeps its package helper anchor across caller directories', {
  skip: process.platform !== 'darwin' || process.arch !== 'arm64'
}, async () => {
  const port = await unusedLoopbackPort()
  const sourceRoot = path.join(repoRoot, 'test', 'contract', 'support_crate_admitted_source')
  const cacheRoot = path.join(repoRoot, '.cache')
  fs.mkdirSync(cacheRoot, { recursive: true })
  const scratch = fs.mkdtempSync(path.join(cacheRoot, 'hxrs-admission-anchor-'))
  const firstCaller = path.join(scratch, 'first')
  const secondCaller = path.join(scratch, 'nested', 'second')
  const shadowRoot = path.join(scratch, 'shadow')
  const shadowHelper = path.join(
    shadowRoot,
    'native',
    'support-crate-admission',
    'darwin-arm64',
    'hxrs-support-crate-admission'
  )
  const shadowMarker = path.join(scratch, 'shadow-was-run')
  fs.mkdirSync(firstCaller, { recursive: true })
  fs.mkdirSync(secondCaller, { recursive: true })
  fs.mkdirSync(path.dirname(shadowHelper), { recursive: true })
  fs.writeFileSync(shadowHelper, `#!/bin/sh\ntouch '${shadowMarker}'\nexit 1\n`, { mode: 0o700 })
  const compilerServer = spawn(haxeServer, ['--wait', String(port)], {
    cwd: repoRoot,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: process.env
  })

  try {
    await waitForCompilerServer(port, compilerServer)
    for (const callerRoot of [firstCaller, secondCaller, firstCaller]) {
      const result = compileAdmittedSourceThroughServer(port, callerRoot, sourceRoot, shadowRoot)
      assert.ifError(result.error)
      assert.notEqual(result.status, 0, 'Stage 3 output unexpectedly became enabled')
      assert.match(transcript(result), /\[HXRS-SUPPORT-CRATE-EMISSION-DISABLED\]/)
      assert.doesNotMatch(transcript(result), /HXRS-SUPPORT-CRATE-SOURCE-ADMISSION-UNAVAILABLE/)
      assert.equal(fs.existsSync(path.join(callerRoot, 'out')), false)
    }
    assert.equal(fs.existsSync(shadowMarker), false,
      'a caller classpath replaced the package-owned admission helper')
  } finally {
    compilerServer.kill('SIGTERM')
    await new Promise(resolve => {
      if (compilerServer.exitCode !== null) return resolve()
      compilerServer.once('exit', resolve)
      setTimeout(() => {
        compilerServer.kill('SIGKILL')
        resolve()
      }, 2000).unref()
    })
    fs.rmSync(scratch, { recursive: true, force: true })
  }
})

test('expression metadata discarded by Haxe cannot request a support crate', () => {
  const fixture = 'support_crate_expression_metadata_ignored'
  const fixtureRoot = path.join(repoRoot, 'test', 'positive', fixture)
  const output = path.join(fixtureRoot, 'out')
  fs.rmSync(output, { recursive: true, force: true })

  try {
    const result = compilePositiveFixture(fixture)
    assert.ifError(result.error)
    assert.equal(result.status, 0, transcript(result))
    assert.equal(fs.existsSync(path.join(output, 'support-crates')), false)
    const manifest = fs.readFileSync(path.join(output, 'Cargo.toml'), 'utf8')
    assert.doesNotMatch(manifest, /native_page_size_support/)
  } finally {
    fs.rmSync(output, { recursive: true, force: true })
  }
})

test('recursive generic constraints compile without support metadata', () => {
  const result = compilePositiveFixture('support_crate_recursive_generic_no_metadata')
  assert.ifError(result.error)
  assert.equal(result.status, 0, transcript(result))
})
