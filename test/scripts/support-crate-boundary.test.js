#!/usr/bin/env node

const assert = require('node:assert/strict')
const fs = require('node:fs')
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

function compileFixture(fixture) {
  return spawnSync(haxe, ['compile.hxml'], {
    cwd: path.join(repoRoot, 'test', 'positive', fixture),
    encoding: 'utf8',
    env: process.env
  })
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

test('reserved support-crate metadata stays rejected through a warm compiler server', async () => {
  const port = await unusedLoopbackPort()
  const fixtureRoot = path.join(repoRoot, 'test', 'contract', 'support_crate_warm_lifecycle')
  const output = path.join(fixtureRoot, 'out')
  const compilerServer = spawn(haxe, ['--wait', String(port)], {
    cwd: repoRoot,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: process.env
  })

  try {
    await waitForCompilerServer(port, compilerServer)

    const safeFirst = compileThroughServer(port, fixtureRoot, false)
    assert.ifError(safeFirst.error)
    assert.equal(safeFirst.status, 0, transcript(safeFirst))
    const safeBytes = fs.readFileSync(path.join(output, 'src', 'main.rs'))

    const reservedFirst = compileThroughServer(port, fixtureRoot, true)
    assert.ifError(reservedFirst.error)
    assert.notEqual(reservedFirst.status, 0, 'reserved metadata unexpectedly compiled through the warm server')
    assert.match(transcript(reservedFirst), /`@:rustSupportCrate` is reserved for the typed support-crate facility/)

    const safeSecond = compileThroughServer(port, fixtureRoot, false)
    assert.ifError(safeSecond.error)
    assert.equal(safeSecond.status, 0, transcript(safeSecond))
    assert.deepEqual(fs.readFileSync(path.join(output, 'src', 'main.rs')), safeBytes,
      'safe output changed after the rejected warm request')

    const reservedSecond = compileThroughServer(port, fixtureRoot, true)
    assert.ifError(reservedSecond.error)
    assert.notEqual(reservedSecond.status, 0, 'the repeated reserved request unexpectedly compiled')
    assert.match(transcript(reservedSecond), /`@:rustSupportCrate` is reserved for the typed support-crate facility/)
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

test('expression metadata discarded by Haxe cannot request a support crate', () => {
  const fixture = 'support_crate_expression_metadata_ignored'
  const fixtureRoot = path.join(repoRoot, 'test', 'positive', fixture)
  const output = path.join(fixtureRoot, 'out')
  fs.rmSync(output, { recursive: true, force: true })

  try {
    const result = compileFixture(fixture)
    assert.ifError(result.error)
    assert.equal(result.status, 0, transcript(result))
    assert.equal(fs.existsSync(path.join(output, 'support-crates')), false)
    const manifest = fs.readFileSync(path.join(output, 'Cargo.toml'), 'utf8')
    assert.doesNotMatch(manifest, /native_page_size_support/)
  } finally {
    fs.rmSync(output, { recursive: true, force: true })
  }
})
