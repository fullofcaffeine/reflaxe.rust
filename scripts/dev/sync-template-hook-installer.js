#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

const rootDir = path.resolve(__dirname, '../..')
const sourcePath = path.join(rootDir, 'scripts/install-git-hooks.sh')
const targetPath = path.join(rootDir, 'templates/basic/scripts/install-git-hooks.sh')
const mode = process.argv[2] || '--check'

if (mode === '--write') {
  fs.copyFileSync(sourcePath, targetPath)
  fs.chmodSync(targetPath, 0o755)
  console.log('[sync-template-hook-installer] wrote templates/basic/scripts/install-git-hooks.sh')
  process.exit(0)
}

if (mode !== '--check') {
  console.error('usage: sync-template-hook-installer.js [--check|--write]')
  process.exit(2)
}

if (!fs.readFileSync(sourcePath).equals(fs.readFileSync(targetPath))) {
  console.error('[sync-template-hook-installer] generated installer is stale; run npm run hooks:sync-template')
  process.exit(1)
}

console.log('[sync-template-hook-installer] OK')
