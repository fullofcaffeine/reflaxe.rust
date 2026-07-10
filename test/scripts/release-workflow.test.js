#!/usr/bin/env node

const assert = require('assert')
const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '..', '..')
const ciPath = path.join(root, '.github', 'workflows', 'ci.yml')
const legacyReleasePath = path.join(root, '.github', 'workflows', 'release.yml')
const repairPath = path.join(root, '.github', 'workflows', 'release-repair.yml')
const weeklyPath = path.join(root, '.github', 'workflows', 'weekly-ci-evidence.yml')
const packagePath = path.join(root, 'package.json')

function requireMatch(text, pattern, message) {
  assert.match(text, pattern, message)
}

function main() {
  const ci = fs.readFileSync(ciPath, 'utf8')
  assert(!ci.includes('workflow_run'), 'normal publication must not cross a privileged workflow_run boundary')
  assert(!fs.existsSync(legacyReleasePath), 'the separate normal Release workflow must be removed')
  requireMatch(ci, /npm audit\n/, 'a successful dependency audit must be part of the release gate')

  const releaseStart = ci.indexOf('\n  release:\n')
  assert(releaseStart !== -1, 'CI must contain a release job')
  const release = ci.slice(releaseStart)
  requireMatch(release, /if: github\.event_name == 'push' && github\.ref == 'refs\/heads\/main'/, 'release must be push/main only')
  for (const required of ['security', 'rust-tooling', 'windows-smoke', 'rustsec-audit', 'test', 'tier2-stdlib-sweep']) {
    requireMatch(release, new RegExp(`- ${required.replace('-', '\\-')}`), `release must wait for ${required}`)
  }
  requireMatch(release, /contents: write/, 'only the release job needs contents write authority')
  requireMatch(release, /group: release-\$\{\{ github\.repository \}\}/, 'all normal publication must serialize in one repository group')
  requireMatch(release, /ref: \$\{\{ github\.sha \}\}/, 'release checkout must use the exact CI-tested SHA')
  requireMatch(release, /actions\/checkout@[0-9a-f]{40}/, 'privileged checkout must pin a full action commit')
  requireMatch(release, /actions\/setup-node@[0-9a-f]{40}/, 'privileged Node setup must pin a full action commit')
  requireMatch(release, /node-version: "22\.14\.0"/, 'release Node runtime must be exact')
  assert(!release.includes('actions/cache'), 'the privileged release job must not restore an executable cache')
  assert(!release.includes('workflow_dispatch'), 'normal publication must not have a manual bypass')

  assert(fs.existsSync(repairPath), 'an existing-tag repair-only workflow must exist')
  const repair = fs.readFileSync(repairPath, 'utf8')
  requireMatch(repair, /workflow_dispatch:/, 'repair must be explicitly manual')
  requireMatch(repair, /tag:\n\s+description:/, 'repair must require a tag input')
  requireMatch(repair, /ref: \$\{\{ inputs\.tag \}\}/, 'repair must check out the supplied immutable tag')
  requireMatch(repair, /REPAIR_TAG: \$\{\{ inputs\.tag \}\}/, 'manual input must cross into shell through an environment value')
  requireMatch(repair, /node scripts\/release\/repair-release\.js "\$REPAIR_TAG"/, 'repair must use the non-version-deriving repair command')
  assert(!repair.includes('semantic-release'), 'repair must never derive or create a new version')
  assert(!repair.includes('git tag'), 'repair must never create, move, or delete a tag')

  assert(fs.existsSync(weeklyPath), 'the sustained-stability evidence workflow must exist')
  const weekly = fs.readFileSync(weeklyPath, 'utf8')
  const packageJson = JSON.parse(fs.readFileSync(packagePath, 'utf8'))
  const ciNode = ci.match(/^  NODE_VERSION: "([^"]+)"$/m)?.[1]
  const weeklyNode = weekly.match(/^  NODE_VERSION: "([^"]+)"$/m)?.[1]
  assert(ciNode, 'CI must declare its exact Node runtime')
  assert.strictEqual(weeklyNode, ciNode, 'weekly evidence and normal CI must use the same Node runtime')
  assert(
    String(packageJson.engines?.node || '').startsWith(`>=${weeklyNode} `),
    'weekly evidence Node must match the package engine minimum'
  )
  requireMatch(weekly, /cron: "0 10 \* \* 1"/, 'weekly evidence must retain the Monday 10:00 UTC cadence')
  requireMatch(weekly, /workflow_dispatch: \{\}/, 'weekly evidence must support deliberate reruns')
  requireMatch(weekly, /group: weekly-ci-evidence-\$\{\{ github\.ref \}\}/, 'weekly evidence runs must serialize per ref')
  requireMatch(weekly, /cancel-in-progress: false/, 'a later trigger must not cancel an evidence run already in progress')
  for (const requiredJob of ['local-equivalent', 'windows-smoke', 'codex-hxrust-qa', 'follow-up-guidance']) {
    requireMatch(weekly, new RegExp(`\\n  ${requiredJob.replaceAll('-', '\\-')}:\\n`), `weekly evidence must retain ${requiredJob}`)
  }
  requireMatch(weekly, /Commit: \\?`\$\{\{ github\.sha \}\}\\?`/, 'Linux weekly evidence must record the exact compiler SHA')
  requireMatch(weekly, /haxe\.rust commit: \\?`\$\{haxe_rust_sha\}\\?`/, 'killer-app evidence must record the compiler SHA')
  requireMatch(weekly, /codex-hxrust commit: \\?`\$\{codex_hxrust_sha\}\\?`/, 'killer-app evidence must record the app SHA')
  for (const requiredNeed of ['local-equivalent', 'windows-smoke', 'codex-hxrust-qa']) {
    requireMatch(weekly, new RegExp(`- ${requiredNeed.replaceAll('-', '\\-')}`), `weekly rollup must wait for ${requiredNeed}`)
  }

  console.log('[release-workflow-test] OK')
}

main()
