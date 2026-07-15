#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

const rootDir = path.resolve(__dirname, '../..')
const hookPath = path.join(rootDir, 'scripts/hooks/pre-commit')
const hook = fs.readFileSync(hookPath, 'utf8')

function requireFragment(fragment, label) {
  if (!hook.includes(fragment)) {
    throw new Error(`pre-commit hook is missing ${label}: ${fragment}`)
  }
}

requireFragment('test/semantic_diff', 'portable semantic-fixture trigger')
requireFragment('test/semantic_diff_lanes', 'lane semantic-fixture trigger')
requireFragment('test/snapshot', 'snapshot-fixture trigger')
requireFragment('docs/semantic-confidence-summary.json', 'JSON artifact staging check')
requireFragment('docs/semantic-confidence-summary.md', 'Markdown artifact staging check')
requireFragment('scripts/ci/check-semantic-confidence-summary.sh', 'deterministic evidence check')
requireFragment('docs/architecture-capability-manifest.json', 'architecture capability manifest trigger')
requireFragment('docs/architecture-capability.md', 'architecture capability generated-page staging check')
requireFragment('scripts/ci/architecture-capability-manifest.js', 'architecture capability drift check')

console.log('[pre-commit-evidence-wiring-test] OK')
