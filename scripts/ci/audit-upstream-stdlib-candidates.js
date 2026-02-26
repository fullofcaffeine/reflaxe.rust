#!/usr/bin/env node

const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const allowlistPath = 'docs/portable-stdlib-allowlist.json'
const tier2Path = 'test/upstream_std_modules_tier2.txt'
const vendoredUpstreamStdRoot = 'vendor/haxe/std'
const outJsonPath = 'docs/portable-stdlib-candidates.json'
const outMdPath = 'docs/portable-stdlib-candidates.md'

function fail(message) {
  console.error(`[stdlib-candidates] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  const flags = new Set()
  for (const arg of argv) {
    if (arg === '--write' || arg === '--check' || arg === '--json') {
      flags.add(arg)
      continue
    }
    if (arg === '-h' || arg === '--help') {
      printUsage()
      process.exit(0)
    }
    fail(`unknown argument: ${arg}`)
  }
  return {
    write: flags.has('--write'),
    check: flags.has('--check'),
    json: flags.has('--json')
  }
}

function printUsage() {
  console.log(`Usage: node scripts/ci/audit-upstream-stdlib-candidates.js [--write] [--check] [--json]

Scans upstream Haxe std modules for importable entries that match the portable contract scope,
then reports which modules are missing from Tier2 sweep coverage.

Options:
  --write   Update ${outJsonPath} and ${outMdPath} with deterministic report artifacts.
  --check   Fail if existing report artifacts differ from computed output.
  --json    Print JSON report to stdout.
`)
}

function parseJson(filePath) {
  if (!fs.existsSync(filePath)) {
    fail(`missing file: ${filePath}`)
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'))
  } catch (error) {
    fail(`invalid JSON in ${filePath}: ${error}`)
  }
}

function parseModuleList(filePath) {
  if (!fs.existsSync(filePath)) {
    fail(`missing module list: ${filePath}`)
  }
  return fs
    .readFileSync(filePath, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.replace(/[ \t]*#.*$/, '').trim())
    .filter((line) => line.length > 0)
}

function removeDirRecursive(dirPath) {
  fs.rmSync(dirPath, { recursive: true, force: true })
}

function resolveUpstreamStdRootFromHaxe() {
  const haxeBin = process.env.HAXE_BIN || 'haxe'
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'reflaxe-rust-stdlib-audit-'))
  const mainPath = path.join(tmpDir, 'Main.hx')
  fs.writeFileSync(mainPath, 'class Main { static function main() {} }\n')
  try {
    const out = cp.execFileSync(haxeBin, ['-cp', tmpDir, '-main', 'Main', '--no-output', '-v'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe']
    })
    const match = out.match(/Parsed (.+[\\/]+std[\\/]+StdTypes\.hx)/)
    if (match == null || typeof match[1] !== 'string') {
      fail(`could not resolve std path from \`${haxeBin} -v\` output`)
    }
    return {
      sourceKind: 'haxe-install',
      path: path.dirname(match[1])
    }
  } catch (error) {
    fail(`failed to resolve std path from Haxe: ${error}`)
  } finally {
    removeDirRecursive(tmpDir)
  }
}

function resolveUpstreamStdRoot() {
  const envRoot = process.env.UPSTREAM_HAXE_STD_PATH
  if (typeof envRoot === 'string' && envRoot.trim().length > 0) {
    if (!fs.existsSync(envRoot)) {
      fail(`UPSTREAM_HAXE_STD_PATH does not exist`)
    }
    return {
      sourceKind: 'env',
      path: envRoot
    }
  }

  if (fs.existsSync(vendoredUpstreamStdRoot)) {
    return {
      sourceKind: 'vendor',
      path: vendoredUpstreamStdRoot
    }
  }

  return resolveUpstreamStdRootFromHaxe()
}

function listHxFiles(dirPath) {
  const entries = fs.readdirSync(dirPath, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const entryPath = path.join(dirPath, entry.name)
    if (entry.isDirectory()) {
      files.push(...listHxFiles(entryPath))
      continue
    }
    if (!entry.isFile() || !entry.name.endsWith('.hx')) {
      continue
    }
    files.push(entryPath)
  }
  files.sort()
  return files
}

function moduleFromUpstreamPath(rootPath, filePath) {
  const relative = path.relative(rootPath, filePath).split(path.sep).join('/')
  if (!relative.endsWith('.hx') || relative.startsWith('..')) {
    return null
  }
  return relative.slice(0, -'.hx'.length).replace(/\//g, '.')
}

function isInScope(moduleName, inScopeRoots) {
  for (const root of inScopeRoots) {
    if (root.endsWith('.')) {
      if (moduleName.startsWith(root)) {
        return true
      }
      continue
    }
    if (moduleName === root) {
      return true
    }
  }
  return false
}

function isExcluded(moduleName, excludedPrefixes) {
  return excludedPrefixes.some((prefix) => moduleName.startsWith(prefix))
}

function uniqueSorted(values) {
  return Array.from(new Set(values)).sort()
}

function summarize(values, limit) {
  const head = values.slice(0, limit)
  if (values.length <= limit) {
    return head
  }
  return [...head, `... (${values.length - limit} more)`]
}

function renderMarkdown(report) {
  const lines = [
    '# Portable Stdlib Candidate Audit',
    '',
    'Deterministic scan of upstream stdlib modules that match the portable contract scope.',
    '',
    `- upstreamStdVersion: \`${report.upstreamStdVersion}\``,
    `- upstreamImportableModules: \`${report.upstreamImportableModules.length}\``,
    `- tier2CoveredModules: \`${report.tier2CoveredModules.length}\``,
    `- missingFromTier2: \`${report.missingFromTier2.length}\``,
    ''
  ]

  lines.push('## Missing From Tier2')
  lines.push('')
  if (report.missingFromTier2.length === 0) {
    lines.push('_none_')
  } else {
    for (const moduleName of report.missingFromTier2) {
      lines.push(`- \`${moduleName}\``)
    }
  }
  lines.push('')
  return lines.join('\n')
}

const args = parseArgs(process.argv.slice(2))
const allowlist = parseJson(allowlistPath)

if (allowlist == null || typeof allowlist !== 'object') {
  fail(`${allowlistPath} must contain a JSON object`)
}
if (!Array.isArray(allowlist.inScopeRoots)) {
  fail(`${allowlistPath} must include inScopeRoots array`)
}
if (!Array.isArray(allowlist.excludedTargetNamespacePrefixes)) {
  fail(`${allowlistPath} must include excludedTargetNamespacePrefixes array`)
}

const upstreamStdRoot = resolveUpstreamStdRoot()

const inScopeRoots = allowlist.inScopeRoots
const excludedPrefixes = allowlist.excludedTargetNamespacePrefixes
const tier2Modules = uniqueSorted(parseModuleList(tier2Path))
const tier2Set = new Set(tier2Modules)

const upstreamImportableModules = uniqueSorted(
  listHxFiles(upstreamStdRoot.path)
    .map((filePath) => moduleFromUpstreamPath(upstreamStdRoot.path, filePath))
    .filter((moduleName) => moduleName != null)
    .filter((moduleName) => isInScope(moduleName, inScopeRoots))
    .filter((moduleName) => !isExcluded(moduleName, excludedPrefixes))
)

const missingFromTier2 = upstreamImportableModules.filter((moduleName) => !tier2Set.has(moduleName))
const coveredInTier2 = upstreamImportableModules.filter((moduleName) => tier2Set.has(moduleName))

const report = {
  schemaVersion: 1,
  contract: 'portable',
  source: {
    allowlistPath,
    tier2Path,
    upstreamStdSourceKind: upstreamStdRoot.sourceKind
  },
  upstreamStdVersion: String(allowlist.upstreamStdVersion || 'unknown'),
  inScopeRoots,
  excludedTargetNamespacePrefixes: excludedPrefixes,
  upstreamImportableModules,
  tier2CoveredModules: coveredInTier2,
  missingFromTier2
}

const jsonContent = `${JSON.stringify(report, null, 2)}\n`
const mdContent = renderMarkdown(report)

if (args.write) {
  fs.writeFileSync(outJsonPath, jsonContent)
  fs.writeFileSync(outMdPath, mdContent)
  console.log(
    `[stdlib-candidates] wrote ${outJsonPath} and ${outMdPath} (${report.missingFromTier2.length} missing modules)`
  )
}

if (args.check) {
  const currentJson = fs.existsSync(outJsonPath) ? fs.readFileSync(outJsonPath, 'utf8') : ''
  const currentMd = fs.existsSync(outMdPath) ? fs.readFileSync(outMdPath, 'utf8') : ''
  if (currentJson !== jsonContent || currentMd !== mdContent) {
    fail(
      `stale candidate report artifacts. Run: node scripts/ci/audit-upstream-stdlib-candidates.js --write`
    )
  }
  console.log(
    `[stdlib-candidates] check OK: ${outJsonPath} and ${outMdPath} are up to date (${report.missingFromTier2.length} missing modules)`
  )
}

if (!args.write && !args.check) {
  console.log(`[stdlib-candidates] upstream importable modules: ${upstreamImportableModules.length}`)
  console.log(`[stdlib-candidates] tier2 covered modules: ${coveredInTier2.length}`)
  console.log(`[stdlib-candidates] missing from tier2: ${missingFromTier2.length}`)
  const preview = summarize(missingFromTier2, 20)
  if (preview.length > 0) {
    console.log('[stdlib-candidates] preview:')
    for (const item of preview) {
      console.log(`  - ${item}`)
    }
  }
}

if (args.json) {
  process.stdout.write(jsonContent)
}
