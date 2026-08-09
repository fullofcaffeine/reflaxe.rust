#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

const rootDir = path.resolve(__dirname, '../..')
const mode = process.argv[2] || '--check'
const ownedFiles = [
  'scripts/dev/cargo-hx.sh',
  'scripts/dev/watch-haxe-rust.sh'
]

function targetFor(source) {
  return path.join(rootDir, 'templates/basic', source)
}

if (mode === '--write') {
  for (const relativeSource of ownedFiles) {
    const source = path.join(rootDir, relativeSource)
    const target = targetFor(relativeSource)
    fs.copyFileSync(source, target)
    fs.chmodSync(target, 0o755)
    console.log(`[sync-template-dev-tools] wrote templates/basic/${relativeSource}`)
  }
  process.exit(0)
}

if (mode !== '--check') {
  console.error('usage: sync-template-dev-tools.js [--check|--write]')
  process.exit(2)
}

for (const relativeSource of ownedFiles) {
  const source = path.join(rootDir, relativeSource)
  const target = targetFor(relativeSource)
  if (!fs.readFileSync(source).equals(fs.readFileSync(target))) {
    console.error(
      `[sync-template-dev-tools] templates/basic/${relativeSource} is stale; ` +
      'run npm run dev:sync-template-tools'
    )
    process.exit(1)
  }
}

console.log('[sync-template-dev-tools] OK')
