#!/usr/bin/env node

const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const repoRoot = path.resolve(__dirname, '..', '..')
const buildScript = path.join(repoRoot, 'tools', 'support-crate-admission-helper', 'build.js')
const packageRoot = path.join(repoRoot, 'native', 'support-crate-admission', 'darwin-arm64')

const checked = spawnSync(process.execPath, [buildScript, '--check'], {
  cwd: repoRoot,
  encoding: 'utf8',
  env: {
    ...process.env,
    RUSTC_WRAPPER: '/nonexistent/hxrs-rustc-wrapper',
    RUSTC_WORKSPACE_WRAPPER: '/nonexistent/hxrs-workspace-wrapper',
    RUSTFLAGS: '--definitely-not-an-admitted-rust-flag',
    CARGO_ENCODED_RUSTFLAGS: '--also-not-admitted',
    CARGO_TARGET_AARCH64_APPLE_DARWIN_LINKER: '/nonexistent/hxrs-linker',
    SDKROOT: '/nonexistent/hxrs-sdk',
    MACOSX_DEPLOYMENT_TARGET: '99.0'
  }
})
assert.ifError(checked.error)
assert.equal(checked.status, 0, `${checked.stdout || ''}${checked.stderr || ''}`)

const inventory = JSON.parse(fs.readFileSync(path.join(packageRoot, 'dependency-inventory.json'), 'utf8'))
assert.equal(inventory.cargoTarget, 'aarch64-apple-darwin')
for (const name of ['linux-raw-sys', 'windows-sys', 'windows-targets', 'redox_syscall']) {
  assert.equal(inventory.packages.some(item => item.name === name), false, `${name} is not a Darwin ARM64 dependency`)
}

const provenance = JSON.parse(fs.readFileSync(path.join(packageRoot, 'binary-provenance.json'), 'utf8'))
assert.deepEqual({
  cargoTarget: provenance.build.cargoTarget,
  deploymentTarget: provenance.build.deploymentTarget,
  rustflags: provenance.build.rustflags,
  cargoEncodedRustflags: provenance.build.cargoEncodedRustflags,
  cargoIncremental: provenance.build.cargoIncremental,
  cargoOffline: provenance.build.cargoOffline
}, {
  cargoTarget: 'aarch64-apple-darwin',
  deploymentTarget: '11.0',
  rustflags: '',
  cargoEncodedRustflags: '',
  cargoIncremental: false,
  cargoOffline: true
})

process.stdout.write(checked.stdout)
