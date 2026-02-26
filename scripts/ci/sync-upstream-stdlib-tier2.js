#!/usr/bin/env node

const fs = require('fs')

const tier1Path = 'test/upstream_std_modules.txt'
const tier2ExtrasPath = 'test/upstream_std_modules_tier2_extras.txt'
const tier2Path = 'test/upstream_std_modules_tier2.txt'

function fail(msg) {
  console.error(`[tier2-sync] ERROR: ${msg}`)
  process.exit(2)
}

function parseModuleList(path) {
  if (!fs.existsSync(path)) {
    fail(`missing module list: ${path}`)
  }
  return fs
    .readFileSync(path, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.replace(/[ \t]*#.*$/, '').trim())
    .filter((line) => line.length > 0)
}

const tier1 = parseModuleList(tier1Path)
const extras = parseModuleList(tier2ExtrasPath)
const merged = Array.from(new Set([...tier1, ...extras])).sort()

const out = [
  '# Broader upstream Haxe std modules for Rust parity sweep (Tier2).',
  '# Tier2 is intended for broader validation outside PR-critical fast loops.',
  ...merged,
  ''
].join('\n')

const previous = fs.existsSync(tier2Path) ? fs.readFileSync(tier2Path, 'utf8') : ''
fs.writeFileSync(tier2Path, out)

const status = previous === out ? 'already in sync' : 'updated'
console.log(
  `[tier2-sync] ${status}: ${tier2Path} <= sort(unique(${tier1Path} + ${tier2ExtrasPath})) (${merged.length} modules)`
)
