#!/usr/bin/env node

/**
 * Run one Cargo command against generated Rust with the reviewed dependency graph.
 *
 * The generated snapshot intentionally does not store Cargo.lock. This helper proves that its
 * Cargo inputs match the reviewed policy case, installs that reviewed lock into a private copy,
 * and then runs one of two exact Cargo commands with --frozen. Mandatory CI therefore checks
 * generated Rust without asking the live registry to choose dependency versions or accepting
 * caller-supplied Cargo flags that could weaken the reviewed build.
 */

const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
const freshCargo = require('./fresh-cargo-resolution.js')

const repoRoot = path.resolve(__dirname, '..', '..')
const commandTimeoutMs = Number.parseInt(process.env.FRESH_CARGO_COMMAND_TIMEOUT_MS || '900000', 10)
const approvedCommands = [
  ['check'],
  ['clippy', '--all-targets', '--', '-A', 'clippy::all', '-D', 'clippy::correctness', '-D', 'clippy::suspicious']
]

function fail(message) {
  throw new Error(`FCR040_REVIEWED_GENERATED_COMMAND: ${message}`)
}

function main() {
  if (!Number.isInteger(commandTimeoutMs) || commandTimeoutMs < 1000) fail('FRESH_CARGO_COMMAND_TIMEOUT_MS must be at least 1000')
  const args = process.argv.slice(2)
  const separator = args.indexOf('--')
  if (separator < 0) fail('expected --case <id> --fixture <path> -- <cargo arguments>')
  const optionArgs = args.slice(0, separator)
  const cargoArgs = args.slice(separator + 1)
  const value = (name) => {
    const indexes = optionArgs.flatMap((argument, index) => argument === name ? [index] : [])
    if (indexes.length !== 1 || indexes[0] + 1 >= optionArgs.length) fail(`${name} must appear exactly once with a value`)
    return optionArgs[indexes[0] + 1]
  }
  if (optionArgs.length !== 4) fail('only --case <id> and --fixture <path> are accepted before --')
  if (cargoArgs.length === 0) fail('Cargo arguments are required')
  if (!approvedCommands.some((approved) => JSON.stringify(approved) === JSON.stringify(cargoArgs))) {
    fail('Cargo arguments must match one reviewed generated-crate command')
  }
  const caseId = value('--case')
  const fixture = path.resolve(repoRoot, value('--fixture'))
  const policy = JSON.parse(fs.readFileSync(path.join(repoRoot, 'rust-toolchain-policy.json'), 'utf8'))
  const entry = policy.dependencyResolution.cases.find((candidate) => candidate.id === caseId)
  if (entry == null) fail(`unknown reviewed case ${caseId}`)
  const baseline = freshCargo.checkBaseline(policy)
  const reviewed = baseline.manifest.cases.find((candidate) => candidate.id === caseId)
  const suppliedDigest = freshCargo.resolutionInputDigest({ ...entry, fixture: path.relative(repoRoot, fixture) })
  if (suppliedDigest !== reviewed.resolutionInputSha256) {
    fail(`${path.relative(repoRoot, fixture)} Cargo inputs do not match reviewed case ${caseId}`)
  }
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-reviewed-generated-'))
  try {
    const crate = path.join(root, 'crate')
    fs.cpSync(fixture, crate, { recursive: true })
    const copiedDigest = freshCargo.resolutionInputDigest({ ...entry, fixture: path.relative(repoRoot, crate) })
    if (copiedDigest !== reviewed.resolutionInputSha256) fail('Cargo inputs changed while the private crate was copied')
    fs.writeFileSync(path.join(crate, 'Cargo.lock'), baseline.artifacts.get(caseId).lock)
    freshCargo.assertNoAncestorCargoConfiguration(crate, crate)
    const toolchain = freshCargo.loadSelectedToolchain()
    const environment = freshCargo.cargoEnvironment(
      path.join(root, 'cargo-home'),
      path.join(root, 'target'),
      toolchain
    )
    const runCargo = (arguments_) => cp.spawnSync(toolchain.cargo, arguments_, {
      cwd: crate,
      env: environment,
      encoding: 'utf8',
      stdio: 'inherit',
      timeout: Number.parseInt(process.env.FRESH_CARGO_COMMAND_TIMEOUT_MS || '900000', 10)
    })
    const fetch = runCargo(['fetch', '--locked', '--quiet', '--manifest-path', path.join(crate, 'Cargo.toml')])
    if (fetch.error != null) throw fetch.error
    if (fetch.status !== 0) return fetch.status == null ? 1 : fetch.status
    const result = runCargo([
      cargoArgs[0], '--frozen', '--manifest-path', path.join(crate, 'Cargo.toml'), ...cargoArgs.slice(1)
    ])
    if (result.error != null) throw result.error
    return result.status == null ? 1 : result.status
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }
}

if (require.main === module) {
  try {
    process.exitCode = main()
  } catch (error) {
    console.error(`[reviewed-generated-cargo] ${error.message}`)
    process.exitCode = 1
  }
}
