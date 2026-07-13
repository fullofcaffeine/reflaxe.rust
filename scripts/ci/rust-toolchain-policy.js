#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const defaultManifestPath = path.join(repoRoot, 'rust-toolchain-policy.json')
const generatedHaxePath = path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustToolchainPolicy.hx')
const generatedTomlPath = path.join(repoRoot, 'rust-toolchain.toml')
const policyDocsPath = path.join(repoRoot, 'docs', 'rust-toolchain-policy.md')
const docsBegin = '<!-- BEGIN GENERATED RUST TOOLCHAIN POLICY -->'
const docsEnd = '<!-- END GENERATED RUST TOOLCHAIN POLICY -->'

function loadManifest(manifestPath) {
  return JSON.parse(fs.readFileSync(manifestPath, 'utf8'))
}

function parseRustVersion(value) {
  const match = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.exec(value || '')
  return match == null ? null : match.slice(1).map((component) => BigInt(component))
}

function compareRustVersions(left, right) {
  const leftParts = parseRustVersion(left)
  const rightParts = parseRustVersion(right)
  if (leftParts == null || rightParts == null) throw new Error('Rust versions must use canonical major.minor.patch form')
  for (let index = 0; index < leftParts.length; index += 1) {
    if (leftParts[index] < rightParts[index]) return -1
    if (leftParts[index] > rightParts[index]) return 1
  }
  return 0
}

function validateManifest(manifest) {
  const errors = []
  if (manifest.schemaVersion !== 1) errors.push('schemaVersion must be 1')
  for (const field of ['minimumSupportedRust', 'releaseToolchain', 'generatedCargoRustVersion']) {
    if (parseRustVersion(manifest[field]) == null) errors.push(`${field} must be canonical major.minor.patch Rust SemVer`)
  }
  if (parseRustVersion(manifest.minimumSupportedRust) != null && parseRustVersion(manifest.releaseToolchain) != null
      && compareRustVersions(manifest.releaseToolchain, manifest.minimumSupportedRust) < 0) {
    errors.push('releaseToolchain must be greater than or equal to minimumSupportedRust')
  }
  if (manifest.generatedCargoRustVersion !== manifest.minimumSupportedRust) {
    errors.push('generatedCargoRustVersion must equal minimumSupportedRust')
  }
  if (manifest.currentStableLane !== 'stable') errors.push('currentStableLane must be stable')
  if (!Number.isInteger(manifest.reviewCadenceWeeks) || manifest.reviewCadenceWeeks < 1) {
    errors.push('reviewCadenceWeeks must be a positive integer')
  }
  if (!Number.isInteger(manifest.minimumFloorRaiseNoticeDays) || manifest.minimumFloorRaiseNoticeDays < 1) {
    errors.push('minimumFloorRaiseNoticeDays must be a positive integer')
  }
  if (manifest.floorRaiseRelease !== 'minor') errors.push('floorRaiseRelease must be minor')
  if (!/^[0-9a-f]{40}$/.test(manifest.setupActionCommit || '')) errors.push('setupActionCommit must be a full commit SHA')
  if (!Array.isArray(manifest.components) || manifest.components.join(',') !== 'rustfmt,clippy') {
    errors.push('components must be exactly rustfmt and clippy')
  }
  return errors
}

function renderHaxe(manifest) {
  return `package reflaxe.rust;

/**
\tGenerated Rust toolchain compatibility constants.

\tWhy
\t- Generated Cargo manifests must reject compilers older than the minimum version actually
\t  exercised by CI.
\t- Keeping this typed compiler consumer generated from rust-toolchain-policy.json prevents the
\t  release runner, documentation, and emitted crate metadata from drifting independently.

\tWhat
\t- MINIMUM_SUPPORTED_RUST is the oldest rustc version in the supported consumer contract.
\t- GENERATED_CARGO_RUST_VERSION is written to the Cargo rust-version field.

\tHow
\t- Run npm run toolchain:sync after reviewing a policy change.
\t- Never edit this file directly; npm run guard:rust-toolchain-policy verifies exact bytes.
**/
class RustToolchainPolicy {
\tpublic static inline final MINIMUM_SUPPORTED_RUST:String = "${manifest.minimumSupportedRust}";
\tpublic static inline final GENERATED_CARGO_RUST_VERSION:String = "${manifest.generatedCargoRustVersion}";
}
`
}

function renderToml(manifest) {
  return `# Generated from rust-toolchain-policy.json by scripts/ci/rust-toolchain-policy.js.
# Local repository work defaults to the supported Rust floor. CI activates each declared lane explicitly.
[toolchain]
channel = "${manifest.minimumSupportedRust}"
profile = "minimal"
components = ["${manifest.components.join('", "')}"]
`
}

function renderDocs(manifest) {
  return `${docsBegin}
- Minimum supported Rust: \`${manifest.minimumSupportedRust}\`
- Reproducible release toolchain: \`${manifest.releaseToolchain}\`
- Compatibility lane: Rust \`${manifest.currentStableLane}\`
- Generated Cargo \`rust-version\`: \`${manifest.generatedCargoRustVersion}\`
- Toolchain/floor review cadence: every ${manifest.reviewCadenceWeeks} weeks
- Minimum notice before a floor raise: ${manifest.minimumFloorRaiseNoticeDays} days
- Earliest project release carrying a floor raise: \`${manifest.floorRaiseRelease}\`
${docsEnd}`
}

function replaceGeneratedDocs(source, block) {
  const begin = source.indexOf(docsBegin)
  const end = source.indexOf(docsEnd)
  if (begin < 0 || end < begin) throw new Error('Rust toolchain policy docs markers are missing or reversed')
  return `${source.slice(0, begin)}${block}${source.slice(end + docsEnd.length)}`
}

function exactField(source, field) {
  const match = source.match(new RegExp(`^${field.replace('-', '\\-')} = "([^"]+)"$`, 'm'))
  return match == null ? null : match[1]
}

function filesUnder(root, fileName) {
  const out = []
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name)
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile() && entry.name === fileName) out.push(full)
    }
  }
  visit(root)
  return out.sort()
}

function checkConsumers(manifest) {
  const errors = []
  const expectedHaxe = renderHaxe(manifest)
  const expectedToml = renderToml(manifest)
  if (!fs.existsSync(generatedHaxePath) || fs.readFileSync(generatedHaxePath, 'utf8') !== expectedHaxe) {
    errors.push('generated RustToolchainPolicy.hx is stale; run npm run toolchain:sync')
  }
  if (!fs.existsSync(generatedTomlPath) || fs.readFileSync(generatedTomlPath, 'utf8') !== expectedToml) {
    errors.push('generated rust-toolchain.toml is stale; run npm run toolchain:sync')
  }
  if (!fs.existsSync(policyDocsPath)) errors.push('docs/rust-toolchain-policy.md is missing')
  else {
    try {
      const docs = fs.readFileSync(policyDocsPath, 'utf8')
      if (replaceGeneratedDocs(docs, renderDocs(manifest)) !== docs) {
        errors.push('generated Rust toolchain policy documentation is stale; run npm run toolchain:sync')
      }
    } catch (error) {
      errors.push(error.message)
    }
  }

  for (const relative of [
    'runtime/hxrt/Cargo.toml',
    'tools/hx/Cargo.toml',
    'templates/basic/tools/hx/Cargo.toml',
    'examples/profile_storyboard/native/Cargo.toml'
  ]) {
    const source = fs.readFileSync(path.join(repoRoot, relative), 'utf8')
    if (exactField(source, 'rust-version') !== manifest.generatedCargoRustVersion) {
      errors.push(`${relative} rust-version must be ${manifest.generatedCargoRustVersion}`)
    }
  }
  for (const cargoPath of filesUnder(path.join(repoRoot, 'test', 'snapshot'), 'Cargo.toml')) {
    const relative = path.relative(repoRoot, cargoPath)
    if (!relative.includes(`${path.sep}intended`) || !fs.readFileSync(cargoPath, 'utf8').includes('[package]')) continue
    if (exactField(fs.readFileSync(cargoPath, 'utf8'), 'rust-version') !== manifest.generatedCargoRustVersion) {
      errors.push(`${relative} rust-version must be ${manifest.generatedCargoRustVersion}`)
    }
  }

  const compiler = fs.readFileSync(path.join(repoRoot, 'src', 'reflaxe', 'rust', 'RustCompiler.hx'), 'utf8')
  if (!compiler.includes("'rust-version = \"' + RustToolchainPolicy.GENERATED_CARGO_RUST_VERSION + '\"'")) {
    errors.push('RustCompiler must emit Cargo rust-version from RustToolchainPolicy')
  }

  const workflowPaths = [
    '.github/workflows/ci.yml',
    '.github/workflows/weekly-ci-evidence.yml',
    '.github/workflows/release-repair.yml',
    '.github/workflows/rustsec.yml'
  ]
  for (const relative of workflowPaths) {
    const source = fs.readFileSync(path.join(repoRoot, relative), 'utf8')
    const refs = Array.from(source.matchAll(/dtolnay\/rust-toolchain@([^\s]+)/g), (match) => match[1])
    if (refs.length === 0) errors.push(`${relative} must set up a Rust toolchain`)
    for (const ref of refs) {
      if (ref !== manifest.setupActionCommit) errors.push(`${relative} uses unapproved Rust setup action ref: ${ref}`)
    }
    const bindings = Array.from(source.matchAll(
      /rust-toolchain-policy\.js --github-output --activate (minimum|release|current)[\s\S]{0,600}?uses: dtolnay\/rust-toolchain@[^\s]+[\s\S]{0,300}?toolchain: \$\{\{ steps\.rust-policy\.outputs\.(minimum|release|current) \}\}/g
    ))
    if (bindings.length !== refs.length) {
      errors.push(`${relative} must explicitly bind every Rust setup action to a policy lane`)
    }
    for (const binding of bindings) {
      if (binding[1] !== binding[2]) {
        errors.push(`${relative} activates Rust lane ${binding[1]} but installs lane ${binding[2]}`)
      }
    }
    if (!source.includes('rust-toolchain-policy.js --github-output')) {
      errors.push(`${relative} must resolve versions from rust-toolchain-policy.json`)
    }
  }

  const ci = fs.readFileSync(path.join(repoRoot, '.github', 'workflows', 'ci.yml'), 'utf8')
  if (!ci.includes('toolchain: ${{ steps.rust-policy.outputs.minimum }}')) errors.push('CI must exercise the minimum Rust lane')
  if (!ci.includes('toolchain: ${{ steps.rust-policy.outputs.current }}')) errors.push('CI must exercise the current stable compatibility lane')
  if ((ci.match(/--github-output --activate minimum/g) || []).length < 8) {
    errors.push('all normal CI Rust jobs must explicitly activate the minimum Rust lane')
  }
  if (!ci.includes('--github-output --activate current')) errors.push('current-stable CI must explicitly activate its Rust lane')
  if (!ci.includes('cargo check --manifest-path "$generated_smoke/Cargo.toml"')) {
    errors.push('current-stable CI must compile representative generated Rust')
  }
  const normalizedCiCommands = ci.replace(/\\\r?\n\s*/g, ' ').replace(/\s+/g, ' ')
  if (!ci.includes('test/snapshot/deny_warnings/intended/.')
      || !normalizedCiCommands.includes('cargo clippy --manifest-path "$generated_clippy/Cargo.toml" --all-targets -- -A clippy::all -D clippy::correctness -D clippy::suspicious')) {
    errors.push('current-stable CI must Clippy-check the representative generated output-quality contract')
  }
  const releaseStart = ci.indexOf('\n  release:\n')
  if (releaseStart < 0 || !ci.slice(releaseStart).includes('toolchain: ${{ steps.rust-policy.outputs.release }}')
      || !ci.slice(releaseStart).includes('--github-output --activate release')) {
    errors.push('release job must use the reproducible release toolchain')
  }

  const weekly = fs.readFileSync(path.join(repoRoot, '.github', 'workflows', 'weekly-ci-evidence.yml'), 'utf8')
  const minimumLaneCount = (weekly.match(/toolchain: \$\{\{ steps\.rust-policy\.outputs\.minimum \}\}/g) || []).length
  if (minimumLaneCount < 3) errors.push('all three weekly evidence jobs must exercise the minimum Rust lane')
  if ((weekly.match(/--github-output --activate minimum/g) || []).length < 3) {
    errors.push('all three weekly evidence jobs must explicitly activate the minimum Rust lane')
  }
  if ((weekly.match(/Rust toolchain: \\?`\$\{rust_version\}\\?`/g) || []).length < 3) {
    errors.push('all three weekly evidence summaries must record the actual Rust toolchain')
  }

  const repair = fs.readFileSync(path.join(repoRoot, '.github', 'workflows', 'release-repair.yml'), 'utf8')
  if (!repair.includes('toolchain: ${{ steps.rust-policy.outputs.release }}')
      || !repair.includes('--github-output --activate release')) errors.push('repair must use the release toolchain')
  const rustsec = fs.readFileSync(path.join(repoRoot, '.github', 'workflows', 'rustsec.yml'), 'utf8')
  if (!rustsec.includes('toolchain: ${{ steps.rust-policy.outputs.release }}')
      || !rustsec.includes('--github-output --activate release')) errors.push('RustSec must use the release toolchain')

  for (const relative of ['README.md', 'docs/install-via-lix.md', 'docs/workflow.md']) {
    const source = fs.readFileSync(path.join(repoRoot, relative), 'utf8')
    if (!source.includes(manifest.minimumSupportedRust)) errors.push(`${relative} must name the minimum supported Rust version`)
  }
  return errors
}

function argumentValue(args, name, fallback) {
  const index = args.indexOf(name)
  return index >= 0 ? args[index + 1] : fallback
}

function reportErrors(errors) {
  for (const error of errors) console.error(`[rust-toolchain-policy] ERROR: ${error}`)
  if (errors.length > 0) process.exit(1)
}

function main() {
  const args = process.argv.slice(2)
  const manifestPath = path.resolve(argumentValue(args, '--manifest', defaultManifestPath))
  let manifest = null
  try {
    manifest = loadManifest(manifestPath)
  } catch (error) {
    reportErrors([`cannot read policy manifest: ${error.message}`])
  }
  const validationErrors = validateManifest(manifest)
  if (args.includes('--validate-only')) {
    reportErrors(validationErrors)
    console.log('[rust-toolchain-policy] manifest OK')
    return
  }
  reportErrors(validationErrors)

  const actualVersion = argumentValue(args, '--assert-supported', null)
  if (actualVersion != null) {
    if (parseRustVersion(actualVersion) == null) {
      return reportErrors([`actual rustc version must be canonical major.minor.patch: ${actualVersion}`])
    }
    if (compareRustVersions(actualVersion, manifest.minimumSupportedRust) < 0) {
      return reportErrors([
        `rustc ${actualVersion} is unsupported; reflaxe.rust requires rustc ${manifest.minimumSupportedRust} or newer`,
        'install the supported repository toolchain from rust-toolchain.toml or upgrade Rust'
      ])
    }
    console.log(`[rust-toolchain-policy] rustc ${actualVersion} satisfies minimum ${manifest.minimumSupportedRust}`)
    return
  }

  const render = argumentValue(args, '--render', null)
  if (render === 'haxe') return process.stdout.write(renderHaxe(manifest))
  if (render === 'toml') return process.stdout.write(renderToml(manifest))
  if (render === 'docs') return process.stdout.write(`${renderDocs(manifest)}\n`)
  if (render != null) return reportErrors([`unknown render target: ${render}`])

  const printLane = argumentValue(args, '--print', null)
  if (printLane != null) {
    const laneVersions = {
      minimum: manifest.minimumSupportedRust,
      release: manifest.releaseToolchain,
      current: manifest.currentStableLane
    }
    if (!Object.hasOwn(laneVersions, printLane)) return reportErrors([`unknown print lane: ${printLane}`])
    process.stdout.write(`${laneVersions[printLane]}\n`)
    return
  }

  if (args.includes('--write')) {
    fs.writeFileSync(generatedHaxePath, renderHaxe(manifest))
    fs.writeFileSync(generatedTomlPath, renderToml(manifest))
    const docs = fs.readFileSync(policyDocsPath, 'utf8')
    fs.writeFileSync(policyDocsPath, replaceGeneratedDocs(docs, renderDocs(manifest)))
    console.log('[rust-toolchain-policy] generated consumers updated')
    return
  }
  if (args.includes('--github-output')) {
    const activeLane = argumentValue(args, '--activate', null)
    const laneVersions = {
      minimum: manifest.minimumSupportedRust,
      release: manifest.releaseToolchain,
      current: manifest.currentStableLane
    }
    if (activeLane != null && !Object.hasOwn(laneVersions, activeLane)) {
      return reportErrors([`unknown activation lane: ${activeLane}`])
    }
    if (activeLane != null && !process.env.GITHUB_ENV) {
      return reportErrors(['--activate requires GITHUB_ENV'])
    }
    const output = [
      `minimum=${manifest.minimumSupportedRust}`,
      `release=${manifest.releaseToolchain}`,
      `current=${manifest.currentStableLane}`
    ].join('\n') + '\n'
    if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, output)
    else process.stdout.write(output)
    if (activeLane != null) {
      fs.appendFileSync(process.env.GITHUB_ENV, `RUSTUP_TOOLCHAIN=${laneVersions[activeLane]}\n`)
    }
    return
  }

  if (args.includes('--check')) {
    reportErrors(checkConsumers(manifest))
    console.log('[rust-toolchain-policy] OK')
    return
  }
  reportErrors(['expected --check, --write, --validate-only, --assert-supported, --github-output, --print, or --render'])
}

if (require.main === module) main()

module.exports = { checkConsumers, compareRustVersions, parseRustVersion, renderDocs, renderHaxe, renderToml, validateManifest }
