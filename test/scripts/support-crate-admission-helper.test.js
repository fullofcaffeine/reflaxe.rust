#!/usr/bin/env node

const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawn, spawnSync } = require('node:child_process')
const test = require('node:test')

const repoRoot = path.resolve(__dirname, '..', '..')
const helperRoot = path.join(repoRoot, 'tools', 'support-crate-admission-helper')
const outputRoot = path.join(helperRoot, 'out')
const barrierOutputRoot = path.join(helperRoot, 'out_barrier')
const haxe = process.env.HAXE_BIN || path.join(
  repoRoot,
  'node_modules',
  '.bin',
  process.platform === 'win32' ? 'haxe.cmd' : 'haxe'
)
const cargo = process.env.CARGO_BIN || 'cargo'
const helperBinary = path.join(
  outputRoot,
  'target',
  'release',
  process.platform === 'win32' ? 'hxrs_support_crate_admission.exe' : 'hxrs_support_crate_admission'
)
const barrierHelperBinary = path.join(
  barrierOutputRoot,
  'target',
  'release',
  process.platform === 'win32' ? 'hxrs_support_crate_admission.exe' : 'hxrs_support_crate_admission'
)

function transcript(result) {
  return `${result.stdout || ''}${result.stderr || ''}`
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd || repoRoot,
    encoding: options.encoding === undefined ? 'utf8' : options.encoding,
    env: process.env,
    input: options.input,
    timeout: options.timeout
  })
  assert.ifError(result.error)
  return result
}

function u16(value) {
  const bytes = Buffer.alloc(2)
  bytes.writeUInt16LE(value)
  return bytes
}

function u32(value) {
  const bytes = Buffer.alloc(4)
  bytes.writeUInt32LE(value)
  return bytes
}

function sized16(value) {
  const bytes = Buffer.from(value, 'utf8')
  return Buffer.concat([u16(bytes.length), bytes])
}

function sized32(value) {
  const bytes = Buffer.from(value, 'utf8')
  return Buffer.concat([u32(bytes.length), bytes])
}

function request(classpaths, declarations) {
  const payload = []
  classpaths.forEach((classpath, index) => {
    payload.push(u32(index), sized32(classpath))
  })
  declarations.forEach((segments, index) => {
    payload.push(u32(index), u16(segments.length), u16(0))
    segments.forEach(segment => payload.push(sized16(segment)))
  })
  const payloadBytes = Buffer.concat(payload)
  return Buffer.concat([
    Buffer.from('HXRSADQ1'),
    u16(1),
    u16(0),
    u32(payloadBytes.length),
    u32(0),
    u16(classpaths.length),
    u16(declarations.length),
    payloadBytes
  ])
}

class Reader {
  constructor(bytes) {
    this.bytes = bytes
    this.offset = 0
  }

  take(length) {
    assert.ok(length >= 0 && this.offset + length <= this.bytes.length, 'response is truncated')
    const value = this.bytes.subarray(this.offset, this.offset + length)
    this.offset += length
    return value
  }

  uint8() {
    return this.take(1).readUInt8()
  }

  uint16() {
    return this.take(2).readUInt16LE()
  }

  uint32() {
    return this.take(4).readUInt32LE()
  }

  int32() {
    return this.take(4).readInt32LE()
  }

  string16() {
    return this.take(this.uint16()).toString('utf8')
  }
}

function decodeResponse(bytes) {
  const reader = new Reader(bytes)
  assert.equal(reader.take(8).toString('ascii'), 'HXRSADR1')
  assert.equal(reader.uint16(), 1)
  assert.equal(reader.uint16(), 0)
  const payloadLength = reader.uint32()
  const status = reader.uint16()
  const bundleCount = reader.uint16()
  assert.equal(reader.uint32(), 0)
  assert.equal(payloadLength, bytes.length - reader.offset)

  if (status === 1) {
    const rejection = {
      status: 'rejected',
      code: reader.uint16(),
      reserved: reader.uint16(),
      declarationRef: reader.int32(),
      classpathRef: reader.int32(),
      componentIndex: reader.int32()
    }
    assert.equal(rejection.reserved, 0)
    assert.equal(bundleCount, 0)
    assert.equal(reader.offset, bytes.length)
    return rejection
  }

  assert.equal(status, 0)
  const bundles = []
  for (let bundleIndex = 0; bundleIndex < bundleCount; bundleIndex += 1) {
    const declarationRef = reader.uint32()
    const classpathRef = reader.uint32()
    const entryCount = reader.uint16()
    assert.equal(reader.uint16(), 0)
    const entries = []
    for (let entryIndex = 0; entryIndex < entryCount; entryIndex += 1) {
      const kind = reader.uint8()
      assert.equal(reader.uint8(), 0)
      const segmentCount = reader.uint16()
      const segments = []
      for (let segmentIndex = 0; segmentIndex < segmentCount; segmentIndex += 1) {
        segments.push(reader.string16())
      }
      const byteLength = reader.uint32()
      entries.push({
        kind: kind === 0 ? 'directory' : 'file',
        path: segments.join('/'),
        bytes: reader.take(byteLength)
      })
    }
    bundles.push({ declarationRef, classpathRef, entries })
  }
  assert.equal(reader.offset, bytes.length)
  return { status: 'accepted', bundles }
}

function runHelper(input, cwd = helperRoot) {
  const result = run(helperBinary, [], { cwd, encoding: null, input })
  assert.equal(result.status, 0, Buffer.from(result.stderr || []).toString('utf8'))
  return decodeResponse(Buffer.from(result.stdout))
}

function waitForFile(file, child) {
  return new Promise((resolve, reject) => {
    const started = Date.now()
    const poll = () => {
      if (fs.existsSync(file)) return resolve()
      if (child.exitCode !== null) return reject(new Error(`helper exited before barrier: ${child.exitCode}`))
      if (Date.now() - started > 10000) return reject(new Error('helper did not reach barrier'))
      setTimeout(poll, 2)
    }
    poll()
  })
}

function startBarrierHelper(input, cwd, ready, release) {
  const child = spawn(barrierHelperBinary, [], {
    cwd,
    env: {
      ...process.env,
      HXRS_ADMISSION_TEST_READY: ready,
      HXRS_ADMISSION_TEST_RELEASE: release
    },
    stdio: ['pipe', 'pipe', 'pipe']
  })
  const stdout = []
  const stderr = []
  child.stdout.on('data', bytes => stdout.push(bytes))
  child.stderr.on('data', bytes => stderr.push(bytes))
  child.stdin.end(input)
  const completed = new Promise((resolve, reject) => {
    child.once('error', reject)
    child.once('close', status => resolve({
      status,
      stdout: Buffer.concat(stdout),
      stderr: Buffer.concat(stderr)
    }))
  })
  return { child, completed }
}

function writeCrate(classpathRoot) {
  const crateRoot = path.join(classpathRoot, 'native', 'sample_support')
  fs.mkdirSync(path.join(crateRoot, 'src', 'foo'), { recursive: true })
  fs.mkdirSync(path.join(crateRoot, 'src', 'platform'), { recursive: true })
  fs.writeFileSync(path.join(crateRoot, 'Cargo.toml'), '[package]\nname = "sample_support"\nversion = "0.1.0"\n')
  fs.writeFileSync(path.join(crateRoot, 'src', 'lib.rs'), 'pub fn answer() -> i32 { 42 }\n')
  fs.writeFileSync(path.join(crateRoot, 'src', 'foo.rs'), 'pub mod foo;\n')
  fs.writeFileSync(path.join(crateRoot, 'src', 'foo', 'bar.rs'), 'pub fn nested() -> bool { true }\n')
  fs.writeFileSync(path.join(crateRoot, 'src', 'platform', 'mod.rs'), 'pub fn supported() -> bool { true }\n')
  return crateRoot
}

function writeSizedCrate(classpathRoot, name, fileCount, fileBytes) {
  const crateRoot = path.join(classpathRoot, 'native', name)
  fs.mkdirSync(path.join(crateRoot, 'src'), { recursive: true })
  fs.writeFileSync(path.join(crateRoot, 'Cargo.toml'), `[package]\nname = "${name}"\nversion = "0.1.0"\n`)
  for (let index = 0; index < fileCount; index += 1) {
    fs.writeFileSync(path.join(crateRoot, 'src', `part_${index}.rs`), Buffer.alloc(fileBytes, 97))
  }
  return crateRoot
}

test.before(() => {
  assert.notEqual(process.platform, 'win32', 'the Stage 2B helper currently targets Unix hosts')
  fs.rmSync(outputRoot, { recursive: true, force: true })

  const compile = run(haxe, ['compile.hxml'], { cwd: helperRoot })
  assert.equal(compile.status, 0, transcript(compile))

  const generatedMain = fs.readFileSync(path.join(outputRoot, 'src', 'main.rs'), 'utf8')
  assert.match(generatedMain, /Generated by reflaxe\.rust/)
  assert.match(generatedMain, /supportcrate_helper_admission_engine::AdmissionEngine/)
  assert.doesNotMatch(
    fs.readFileSync(path.join(helperRoot, 'native', 'support_crate_admission_fs.rs'), 'utf8'),
    /\bunsafe\b/,
    'the narrow native facade must use only safe Rust APIs'
  )

  fs.copyFileSync(path.join(helperRoot, 'Cargo.lock'), path.join(outputRoot, 'Cargo.lock'))
  const build = run(cargo, [
    'build',
    '--release',
    '--locked',
    '--manifest-path',
    path.join(outputRoot, 'Cargo.toml')
  ])
  assert.equal(build.status, 0, transcript(build))
  assert.equal(fs.existsSync(helperBinary), true)

  fs.rmSync(barrierOutputRoot, { recursive: true, force: true })
  const barrierCompile = run(haxe, [
    'compile.hxml',
    '-D', 'support_crate_admission_test_barriers',
    '-D', `rust_output=${barrierOutputRoot}`
  ], { cwd: helperRoot })
  assert.equal(barrierCompile.status, 0, transcript(barrierCompile))
  fs.copyFileSync(path.join(helperRoot, 'Cargo.lock'), path.join(barrierOutputRoot, 'Cargo.lock'))
  const barrierBuild = run(cargo, [
    'build',
    '--release',
    '--locked',
    '--manifest-path',
    path.join(barrierOutputRoot, 'Cargo.toml')
  ])
  assert.equal(barrierBuild.status, 0, transcript(barrierBuild))
  assert.equal(fs.existsSync(barrierHelperBinary), true)
})

test('the Metal-generated helper admits one complete, byte-exact source tree', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-valid-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    writeCrate(classpathRoot)
    const response = runHelper(request([fs.realpathSync(classpathRoot)], [['native', 'sample_support']]))
    assert.equal(response.status, 'accepted')
    assert.equal(response.bundles.length, 1)
    assert.equal(response.bundles[0].declarationRef, 0)
    assert.equal(response.bundles[0].classpathRef, 0)
    assert.deepEqual(
      response.bundles[0].entries.map(entry => ({
        kind: entry.kind,
        path: entry.path,
        bytes: entry.bytes.toString('utf8')
      })),
      [
        {
          kind: 'file',
          path: 'Cargo.toml',
          bytes: '[package]\nname = "sample_support"\nversion = "0.1.0"\n'
        },
        { kind: 'directory', path: 'src', bytes: '' },
        { kind: 'directory', path: 'src/foo', bytes: '' },
        { kind: 'file', path: 'src/foo.rs', bytes: 'pub mod foo;\n' },
        { kind: 'file', path: 'src/foo/bar.rs', bytes: 'pub fn nested() -> bool { true }\n' },
        { kind: 'file', path: 'src/lib.rs', bytes: 'pub fn answer() -> i32 { 42 }\n' },
        { kind: 'directory', path: 'src/platform', bytes: '' },
        { kind: 'file', path: 'src/platform/mod.rs', bytes: 'pub fn supported() -> bool { true }\n' }
      ]
    )
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('relative classpaths may walk to a real parent without turning the source root into a path lookup', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-relative-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    writeCrate(classpathRoot)
    const cwd = path.join(root, 'work', 'nested')
    fs.mkdirSync(cwd, { recursive: true })
    const relativeClasspath = path.relative(cwd, classpathRoot)
    const response = runHelper(request([relativeClasspath], [['native', 'sample_support']]), cwd)
    assert.equal(response.status, 'accepted')
    assert.equal(response.bundles[0].classpathRef, 0)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('an empty classpath binds to the inherited current directory', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-empty-classpath-'))
  try {
    writeCrate(root)
    const response = runHelper(request([''], [['native', 'sample_support']]), root)
    assert.equal(response.status, 'accepted')
    assert.equal(response.bundles[0].classpathRef, 0)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('the same source root through two classpath bindings is ambiguous', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-ambiguous-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    writeCrate(classpathRoot)
    const resolvedClasspath = fs.realpathSync(classpathRoot)
    const response = runHelper(request([resolvedClasspath, resolvedClasspath], [['native', 'sample_support']]))
    assert.deepEqual(response, {
      status: 'rejected',
      code: 4,
      reserved: 0,
      declarationRef: 0,
      classpathRef: -1,
      componentIndex: -1
    })
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('equivalent empty and current-directory classpaths remain ambiguous', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-current-alias-'))
  try {
    writeCrate(root)
    const response = runHelper(request(['', './'], [['native', 'sample_support']]), root)
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 4)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('a classpath that is not a directory is rejected', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-wrong-classpath-kind-'))
  try {
    const classpathFile = path.join(root, 'classpath-file')
    fs.writeFileSync(classpathFile, 'not a directory')
    const response = runHelper(request([classpathFile], [['native', 'sample_support']]))
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 2)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('a symlink in the classpath locator is rejected instead of followed', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-classpath-link-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    writeCrate(classpathRoot)
    const alias = path.join(root, 'classpath-alias')
    fs.symlinkSync(classpathRoot, alias, 'dir')
    const response = runHelper(request([alias], [['native', 'sample_support']]))
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 2)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('a symlink inside the selected source tree is rejected instead of copied', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-tree-link-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    const crateRoot = writeCrate(classpathRoot)
    fs.symlinkSync(path.join(crateRoot, 'Cargo.toml'), path.join(crateRoot, 'Cargo.alias.toml'))
    const response = runHelper(request([fs.realpathSync(classpathRoot)], [['native', 'sample_support']]))
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 5)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('a hard link inside the selected source tree is rejected instead of copied twice', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-tree-hard-link-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    const crateRoot = writeCrate(classpathRoot)
    fs.linkSync(path.join(crateRoot, 'src', 'lib.rs'), path.join(crateRoot, 'src', 'alias.rs'))
    const response = runHelper(request([fs.realpathSync(classpathRoot)], [['native', 'sample_support']]))
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 5)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('a FIFO inside the selected source tree is rejected without waiting for a writer', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-tree-fifo-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    const crateRoot = writeCrate(classpathRoot)
    const fifo = run('mkfifo', [path.join(crateRoot, 'src', 'blocked.rs')])
    assert.equal(fifo.status, 0, transcript(fifo))
    const result = run(helperBinary, [], {
      cwd: root,
      encoding: null,
      input: request([fs.realpathSync(classpathRoot)], [['native', 'sample_support']]),
      timeout: 1000
    })
    assert.equal(result.signal, null, 'the helper must not time out while opening a FIFO')
    assert.equal(result.status, 0, Buffer.from(result.stderr || []).toString('utf8'))
    const response = decodeResponse(Buffer.from(result.stdout))
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 5)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('a source file above the per-file byte limit is rejected', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-large-file-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    const crateRoot = writeCrate(classpathRoot)
    fs.writeFileSync(path.join(crateRoot, 'src', 'large.rs'), Buffer.alloc(2 * 1024 * 1024 + 1, 97))
    const response = runHelper(request([fs.realpathSync(classpathRoot)], [['native', 'sample_support']]))
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 5)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('a source path deeper than 32 components is rejected', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-deep-tree-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    const crateRoot = writeCrate(classpathRoot)
    let current = path.join(crateRoot, 'deep')
    for (let index = 0; index < 32; index += 1) current = path.join(current, `d${index}`)
    fs.mkdirSync(current, { recursive: true })
    fs.writeFileSync(path.join(current, 'too-deep.rs'), '')
    const response = runHelper(request([fs.realpathSync(classpathRoot)], [['native', 'sample_support']]))
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 5)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('directory enumeration stops at the remaining entry budget', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-entry-budget-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    const crateRoot = writeCrate(classpathRoot)
    const crowded = path.join(crateRoot, 'crowded')
    fs.mkdirSync(crowded)
    for (let index = 0; index < 256 * 33; index += 1) {
      fs.mkdirSync(path.join(crowded, `d${String(index).padStart(4, '0')}`))
    }
    const response = runHelper(request([fs.realpathSync(classpathRoot)], [['native', 'sample_support']]))
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 5)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('the 32 MiB source budget applies across all selected crates', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-total-budget-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    const fileBytes = 2 * 1024 * 1024 - 1024
    writeSizedCrate(classpathRoot, 'large_a', 6, fileBytes)
    writeSizedCrate(classpathRoot, 'large_b', 6, fileBytes)
    writeSizedCrate(classpathRoot, 'large_c', 6, fileBytes)
    const response = runHelper(request(
      [fs.realpathSync(classpathRoot)],
      [
        ['native', 'large_a'],
        ['native', 'large_b'],
        ['native', 'large_c']
      ]
    ))
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 5)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('an in-place mutation between complete reads is rejected as changed', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-mutated-read-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    const crateRoot = writeCrate(classpathRoot)
    const ready = path.join(root, 'ready')
    const release = path.join(root, 'release')
    const running = startBarrierHelper(
      request([fs.realpathSync(classpathRoot)], [['native', 'sample_support']]),
      root,
      ready,
      release
    )
    await waitForFile(ready, running.child)
    fs.writeFileSync(path.join(crateRoot, 'src', 'lib.rs'), 'pub fn answer() -> i32 { 7 }\n')
    fs.writeFileSync(release, '')
    const result = await running.completed
    assert.equal(result.status, 0, result.stderr.toString('utf8'))
    assert.equal(result.stderr.length, 0)
    const response = decodeResponse(result.stdout)
    assert.equal(response.status, 'rejected')
    assert.equal(response.code, 6)
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('replacing a pathname cannot redirect a pinned source directory', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-admission-pinned-root-'))
  try {
    const classpathRoot = path.join(root, 'classpath')
    const crateRoot = writeCrate(classpathRoot)
    const ready = path.join(root, 'ready')
    const release = path.join(root, 'release')
    const running = startBarrierHelper(
      request([fs.realpathSync(classpathRoot)], [['native', 'sample_support']]),
      root,
      ready,
      release
    )
    await waitForFile(ready, running.child)
    fs.renameSync(crateRoot, `${crateRoot}-original`)
    const replacement = writeCrate(classpathRoot)
    fs.writeFileSync(path.join(replacement, 'src', 'lib.rs'), 'pub fn answer() -> i32 { 7 }\n')
    fs.writeFileSync(release, '')
    const result = await running.completed
    assert.equal(result.status, 0, result.stderr.toString('utf8'))
    assert.equal(result.stderr.length, 0)
    const response = decodeResponse(result.stdout)
    assert.equal(response.status, 'accepted')
    const library = response.bundles[0].entries.find(entry => entry.path === 'src/lib.rs')
    assert.equal(library.bytes.toString('utf8'), 'pub fn answer() -> i32 { 42 }\n')
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
})

test('malformed input receives a closed protocol rejection', () => {
  assert.deepEqual(runHelper(Buffer.from([0])), {
    status: 'rejected',
    code: 2,
    reserved: 0,
    declarationRef: -1,
    classpathRef: -1,
    componentIndex: -1
  })
})
