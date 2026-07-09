#!/usr/bin/env node

const command = require('path').basename(process.argv[1])
const version = process.env.RELEASE_STATE_FIXTURE_VERSION
const args = process.argv.slice(2)

if (command === 'git') {
  if (args[0] === 'rev-parse' && process.env.RELEASE_STATE_FIXTURE_MISSING_TAG === '1') {
    process.stderr.write('fixture tag missing\n')
    process.exit(1)
  }
  if (args[0] === 'show') {
    const separator = args[1].indexOf(':')
    const relativePath = args[1].slice(separator + 1)
    if (process.env.RELEASE_STATE_FIXTURE_TAG_DRIFT === '1' && relativePath === 'docs/index.md') {
      process.stdout.write('stale tagged posture\n')
      process.exit(0)
    }
    process.stdout.write(require('fs').readFileSync(require('path').join(process.cwd(), relativePath), 'utf8'))
    process.exit(0)
  }
  process.stdout.write('fixture-tag-commit\n')
  process.exit(0)
}

if (command === 'unzip') {
  if (args[args.length - 1] === 'README.md') {
    process.stdout.write(require('fs').readFileSync(require('path').join(process.cwd(), 'README.md'), 'utf8'))
    process.exit(0)
  }
  process.stdout.write(`${JSON.stringify({ version, releasenote: `v${version}: See CHANGELOG.md` })}\n`)
  process.exit(0)
}

if (command === 'gh') {
  const assets = process.env.RELEASE_STATE_FIXTURE_MISSING_ASSET === '1'
    ? []
    : [{ name: `reflaxe.rust-${version}.zip` }]
  process.stdout.write(`${JSON.stringify({
    tagName: `v${version}`,
    isDraft: false,
    isPrerelease: process.env.RELEASE_STATE_FIXTURE_PRERELEASE === '1',
    assets
  })}\n`)
  process.exit(0)
}

process.stderr.write(`unexpected fixture command: ${command}\n`)
process.exit(2)
