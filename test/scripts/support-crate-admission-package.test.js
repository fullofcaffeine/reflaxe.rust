#!/usr/bin/env node

const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const repoRoot = path.resolve(__dirname, '..', '..')
const buildScript = path.join(repoRoot, 'tools', 'support-crate-admission-helper', 'build.js')
const packageRoot = path.join(repoRoot, 'native', 'support-crate-admission', 'darwin-arm64')

function runBuild(environment = {}) {
  const env = { ...process.env, ...environment }
  if (!Object.prototype.hasOwnProperty.call(environment, 'HAXE_BIN')) delete env.HAXE_BIN
  return spawnSync(process.execPath, [buildScript, '--check'], {
    cwd: repoRoot,
    encoding: 'utf8',
    env
  })
}

const checked = runBuild({
    RUSTC_WRAPPER: '/nonexistent/hxrs-rustc-wrapper',
    RUSTC_WORKSPACE_WRAPPER: '/nonexistent/hxrs-workspace-wrapper',
    RUSTFLAGS: '--definitely-not-an-admitted-rust-flag',
    CARGO_ENCODED_RUSTFLAGS: '--also-not-admitted',
    CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER: '/nonexistent/hxrs-linker',
    SDKROOT: '/nonexistent/hxrs-sdk',
    MACOSX_DEPLOYMENT_TARGET: '99.0',
    HAXE_STD_PATH: '/nonexistent/hxrs-haxe-std',
    HAXE_LIBRARY_PATH: '/nonexistent/hxrs-haxe-libraries',
    HAXE_LIBCACHE: '/nonexistent/hxrs-haxe-cache',
    HAXESHIM_LIBCACHE: '/nonexistent/hxrs-haxeshim-cache'
})
assert.ifError(checked.error)
assert.equal(checked.status, 0, `${checked.stdout || ''}${checked.stderr || ''}`)

const inventory = JSON.parse(fs.readFileSync(path.join(packageRoot, 'dependency-inventory.json'), 'utf8'))
assert.equal(inventory.cargoTarget, 'aarch64-apple-darwin')
for (const name of ['linux-raw-sys', 'windows-sys', 'windows-targets', 'redox_syscall']) {
  assert.equal(inventory.packages.some(item => item.name === name), false, `${name} is not a Darwin ARM64 dependency`)
}

const provenance = JSON.parse(fs.readFileSync(path.join(packageRoot, 'binary-provenance.json'), 'utf8'))
assert.ok(provenance.sourceInputs.repositoryFileCount > 0)
assert.ok(provenance.sourceInputs.haxeStdFileCount > 0)
assert.match(provenance.sourceInputs.sha256, /^[0-9a-f]{64}$/)
assert.match(provenance.toolchain.haxeLauncherSha256, /^[0-9a-f]{64}$/)
assert.match(provenance.toolchain.haxeCompilerSha256, /^[0-9a-f]{64}$/)
assert.ok(provenance.toolchain.haxeStd.fileCount > 0)
assert.match(provenance.toolchain.haxeStd.sha256, /^[0-9a-f]{64}$/)
assert.deepEqual({
  cargoTarget: provenance.build.cargoTarget,
  deploymentTarget: provenance.build.deploymentTarget,
  rustflags: provenance.build.rustflags,
  cargoEncodedRustflags: provenance.build.cargoEncodedRustflags,
  cargoIncremental: provenance.build.cargoIncremental,
  cargoOffline: provenance.build.cargoOffline,
  cargoVendored: provenance.build.cargoVendored
}, {
  cargoTarget: 'aarch64-apple-darwin',
  deploymentTarget: '11.0',
  rustflags: '',
  cargoEncodedRustflags: '',
  cargoIncremental: false,
  cargoOffline: true,
  cargoVendored: true
})

const hostileRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-hostile-haxe-'))
const hostileHaxe = path.join(hostileRoot, 'haxe-wrapper.js')
const admittedHaxeShim = path.join(repoRoot, 'node_modules', '.bin', 'haxe')
fs.writeFileSync(hostileHaxe, `#!/usr/bin/env node
const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
if (process.argv[2] === '--version') {
  process.stdout.write('4.3.7\\n')
  process.exit(0)
}
const result = spawnSync(${JSON.stringify(admittedHaxeShim)}, process.argv.slice(2), {
  cwd: process.cwd(),
  env: process.env,
  stdio: 'inherit'
})
if (result.status === 0) {
  const output = process.argv.find(value => value.startsWith('rust_output='))
  if (output) fs.appendFileSync(path.join(process.cwd(), output.slice('rust_output='.length), 'src', 'main.rs'), '\\n// hostile wrapper changed generated source\\n')
}
process.exit(result.status === null ? 1 : result.status)
`)
fs.chmodSync(hostileHaxe, 0o755)
const hostileHaxeResult = runBuild({ HAXE_BIN: hostileHaxe })
assert.ifError(hostileHaxeResult.error)
assert.notEqual(hostileHaxeResult.status, 0, 'a caller-controlled Haxe wrapper must not enter package evidence')
assert.match(
  `${hostileHaxeResult.stdout || ''}${hostileHaxeResult.stderr || ''}`,
  /HAXE_BIN is not admitted for the support-crate helper package build/
)

const poisonedCargoHome = fs.mkdtempSync(path.join(os.tmpdir(), 'hxrs-poisoned-cargo-home-'))
const registryRoot = path.join(poisonedCargoHome, 'registry')
fs.mkdirSync(path.join(registryRoot, 'src'), { recursive: true })
for (const directory of ['index', 'cache']) {
  fs.symlinkSync(path.join(os.homedir(), '.cargo', 'registry', directory), path.join(registryRoot, directory), 'dir')
}
const registrySourceRoot = fs.readdirSync(path.join(os.homedir(), '.cargo', 'registry', 'src'))
  .map(name => path.join(os.homedir(), '.cargo', 'registry', 'src', name))
  .find(candidate => fs.existsSync(path.join(candidate, 'rustix-1.1.4')))
assert.ok(registrySourceRoot, 'the focused package test requires the locked rustix source in the local Cargo cache')
const poisonedIndex = path.basename(registrySourceRoot)
const poisonedRustix = path.join(registryRoot, 'src', poisonedIndex, 'rustix-1.1.4')
fs.mkdirSync(path.dirname(poisonedRustix), { recursive: true })
fs.cpSync(path.join(registrySourceRoot, 'rustix-1.1.4'), poisonedRustix, { recursive: true })
fs.appendFileSync(path.join(poisonedRustix, 'src', 'lib.rs'), '\ncompile_error!("ambient Cargo cache entered the package build");\n')
const poisonedCargoResult = runBuild({ CARGO_HOME: poisonedCargoHome })
assert.ifError(poisonedCargoResult.error)
assert.equal(
  poisonedCargoResult.status,
  0,
  `ambient Cargo cache bytes must not enter the package build:\n${poisonedCargoResult.stdout || ''}${poisonedCargoResult.stderr || ''}`
)

fs.rmSync(hostileRoot, { recursive: true, force: true })
fs.rmSync(poisonedCargoHome, { recursive: true, force: true })
process.stdout.write(checked.stdout)
