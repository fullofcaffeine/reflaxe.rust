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
requireFragment('test:rust-raw-authority', 'typed raw-Rust authority contract')
requireFragment('cmp -s "$ROOT_DIR/scripts/hooks/pre-commit" "$installed_repo_hook"', 'installed-hook freshness check')
requireFragment('pre-commit.old', 'Beads chained-hook freshness target')
requireFragment('npm run hooks:install', 'installed-hook refresh guidance')

const unsafeStagedPipe = `printf '%s\\n' "$STAGED_FILES" | grep -Eq`
if (hook.includes(unsafeStagedPipe)) {
  throw new Error('staged-file triggers must not combine pipefail with a grep -q pipeline')
}
const stagedHereStringCount = hook.split('<<<"$STAGED_FILES"').length - 1
if (stagedHereStringCount < 3) {
  throw new Error(`expected all staged-file trigger groups to use a here-string, found ${stagedHereStringCount}`)
}

console.log('[pre-commit-evidence-wiring-test] OK')
