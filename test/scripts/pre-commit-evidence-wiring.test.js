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
requireFragment('testing-surface-scorecards\\.(json|md)', 'testing product-surface scorecard trigger')
requireFragment('docs/testing-surface-scorecards.md', 'testing scorecard generated-page staging check')
requireFragment('test:testing-surface-scorecards', 'testing scorecard mutation contract')
requireFragment('test:rust-raw-authority', 'typed raw-Rust authority contract')
requireFragment('rust-raw-authority-policy\\.json', 'raw-authority single-source policy trigger')
requireFragment('rust-raw-authority-policy\\.js', 'raw-authority generator trigger')
requireFragment('(src|std|runtime)/.*\\.hx', 'complete raw-authority scan-root trigger')
requireFragment('docs/rust-raw-authority-inventory.json', 'raw-authority reviewed inventory staging check')
requireFragment('git ls-files --error-unmatch docs/rust-raw-authority-inventory.json',
  'raw-authority inventory tracked-or-staged check')
requireFragment('test:rust-structural-path-ir', 'structural Rust path IR contract')
requireFragment('test:rust-structural-type-declarations', 'structural Rust type declaration contract')
requireFragment('test:rust-structural-expression-paths', 'structural Rust expression path contract')
requireFragment('test:rust-structural-pass-analysis', 'structural Rust pass analysis contract')
requireFragment('test:rust-structural-member-closures', 'structural Rust member and closure contract')
requireFragment('test:rust-structural-items', 'structural Rust item contract')
requireFragment('test:rust-structural-trait-impls', 'structural Rust trait and impl contract')
requireFragment('test:rust-source-map', 'deterministic Rust source-map contract')
requireFragment('rust-source-map-policy\\.json', 'source-map generated-reason policy trigger')
requireFragment('rust-source-map-policy\\.js', 'source-map policy generator trigger')
requireFragment('test:rust-representation-plan', 'typed Rust representation-plan contract')
requireFragment('rust-representation-policy\\.json', 'representation-plan single-source policy trigger')
requireFragment('rust-representation-policy\\.js', 'representation-plan generator trigger')
requireFragment('runtime-plan-v4', 'runtime-plan reason vocabulary trigger')
requireFragment('generated-consumer-contract', 'generated-consumer reason vocabulary trigger')
requireFragment('END REFLAXE.RUST REPOSITORY PRE-COMMIT', 'explicit repository-hook boundary')
requireFragment('cmp -s "$ROOT_DIR/scripts/hooks/pre-commit"', 'installed-hook freshness check')
requireFragment('npm run hooks:install', 'installed-hook refresh guidance')

if (hook.includes('bd hooks run pre-commit')) {
  throw new Error('the repository hook must not invoke the outer Beads pre-commit shim')
}
if (hook.includes('pre-commit.old')) {
  throw new Error('the repository hook must not select a legacy chained hook by filename')
}

const unsafeStagedPipe = `printf '%s\\n' "$STAGED_FILES" | grep -Eq`
if (hook.includes(unsafeStagedPipe)) {
  throw new Error('staged-file triggers must not combine pipefail with a grep -q pipeline')
}
const stagedHereStringCount = hook.split('<<<"$STAGED_FILES"').length - 1
if (stagedHereStringCount < 3) {
  throw new Error(`expected all staged-file trigger groups to use a here-string, found ${stagedHereStringCount}`)
}

console.log('[pre-commit-evidence-wiring-test] OK')
