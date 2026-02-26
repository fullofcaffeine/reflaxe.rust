#!/usr/bin/env node

const fs = require('fs')

const allowlistPath = 'docs/portable-stdlib-allowlist.json'
const sweepListPath = 'test/upstream_std_modules.txt'

function fail(msg) {
  console.error(`[stdlib-sync] ERROR: ${msg}`)
  process.exit(2)
}

function parseSweepModules(path) {
  if (!fs.existsSync(path)) {
    fail(`missing module list: ${path}`)
  }
  return fs
    .readFileSync(path, 'utf8')
    .split(/\r?\n/)
    .map((line) => line.replace(/[ \t]*#.*$/, '').trim())
    .filter((line) => line.length > 0)
}

if (!fs.existsSync(allowlistPath)) {
  fail(`missing allowlist file: ${allowlistPath}`)
}

let allowlist = null
try {
  allowlist = JSON.parse(fs.readFileSync(allowlistPath, 'utf8'))
} catch (error) {
  fail(`invalid JSON in ${allowlistPath}: ${error}`)
}

if (allowlist == null || typeof allowlist !== 'object') {
  fail(`${allowlistPath} must contain a JSON object`)
}

const modules = parseSweepModules(sweepListPath)
const previous = Array.isArray(allowlist.tier1UpstreamSweepModules)
  ? allowlist.tier1UpstreamSweepModules
  : []

allowlist.tier1UpstreamSweepModules = modules
fs.writeFileSync(allowlistPath, `${JSON.stringify(allowlist, null, 2)}\n`)

const changed =
  previous.length !== modules.length ||
  previous.some((value, index) => value !== modules[index])
const status = changed ? 'updated' : 'already in sync'
console.log(
  `[stdlib-sync] ${status}: ${allowlistPath} <= ${sweepListPath} (${modules.length} modules)`
)
