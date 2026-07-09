#!/usr/bin/env node

/**
 * Why
 * A release is not complete when source metadata merely says a new version. The historical 1.0
 * drift happened precisely because metadata changed without a matching tag and published release.
 *
 * What
 * Verify the externally meaningful release result for one manifest-supported version: generated
 * repository state, changelog entry, prepared release commit, Git tag, packaged haxelib version,
 * and (when requested) the GitHub Release plus expected zip asset.
 *
 * How
 * Reuse the same generator in check mode, then inspect the release outputs without mutating them.
 * Semantic-release invokes `--prepared` after its release commit and before tag creation, the
 * default mode after tag creation and before GitHub publication, and `--published` from its success
 * lifecycle after publishing completes.
 */

const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')
const { buildReleaseState, parseSemver, staleGeneratedFiles } = require('./sync-versions.js')

function parseArgs(argv) {
  let root = process.cwd()
  let prepared = false
  let published = false
  let version = null

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === '--root') {
      const value = argv[index + 1]
      if (!value) throw new Error('--root requires a path')
      root = path.resolve(value)
      index += 1
      continue
    }
    if (arg === '--published') {
      published = true
      continue
    }
    if (arg === '--prepared') {
      prepared = true
      continue
    }
    if (arg.startsWith('--')) throw new Error(`unknown argument: ${arg}`)
    if (version !== null) throw new Error(`unexpected extra version argument: ${arg}`)
    version = arg
  }

  if (version === null) throw new Error('version argument is required')
  if (prepared && published) throw new Error('--prepared and --published are mutually exclusive')
  return { root, prepared, published, version }
}

function command(commandName, args, root) {
  return execFileSync(commandName, args, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe']
  })
}

function verifyRefFiles(root, ref, label, state, changelog, errors) {
  const expectedFiles = new Map(state.updates)
  expectedFiles.set('release-manifest.json', fs.readFileSync(path.join(root, 'release-manifest.json'), 'utf8'))
  expectedFiles.set('CHANGELOG.md', changelog)

  for (const [relativePath, expected] of [...expectedFiles.entries()].sort(([left], [right]) => left.localeCompare(right))) {
    try {
      const committed = command('git', ['show', `${ref}:${relativePath}`], root)
      if (committed !== expected) {
        errors.push(`${relativePath}: ${label} does not match generated release state`)
      }
    } catch (_error) {
      errors.push(`${relativePath}: missing from ${label}`)
    }
  }
}

function hasChangelogVersion(changelog, version) {
  const escaped = version.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  return new RegExp(`^#{1,2} \\[${escaped}\\](?:\\(|\\s)`, 'm').test(changelog)
}

function verifyReleaseState(root, version, options = {}) {
  const errors = []
  const prepared = Boolean(options.prepared)
  const published = Boolean(options.published)
  const semver = parseSemver(version)
  const state = buildReleaseState(root, semver.raw)

  for (const relativePath of staleGeneratedFiles(root, state)) {
    errors.push(`${relativePath}: generated release state is stale`)
  }

  const changelog = fs.readFileSync(path.join(root, 'CHANGELOG.md'), 'utf8')
  if (!hasChangelogVersion(changelog, semver.raw)) {
    errors.push(`CHANGELOG.md is missing a release heading for ${semver.raw}`)
  }

  const tag = `v${semver.raw}`
  if (prepared) {
    verifyRefFiles(root, 'HEAD', 'prepared release content', state, changelog, errors)
  } else {
    let tagExists = true
    try {
      command('git', ['rev-parse', '--verify', `refs/tags/${tag}^{commit}`], root)
    } catch (_error) {
      tagExists = false
      errors.push(`Git tag ${tag} is missing or does not resolve to a commit`)
    }
    if (tagExists) {
      verifyRefFiles(root, tag, 'tagged release content', state, changelog, errors)
    }
  }

  const assetName = `reflaxe.rust-${semver.raw}.zip`
  const assetPath = path.join(root, 'dist', assetName)
  if (!fs.existsSync(assetPath)) {
    errors.push(`release artifact dist/${assetName} is missing`)
  } else {
    try {
      const packagedHaxelib = JSON.parse(command('unzip', ['-p', assetPath, 'haxelib.json'], root))
      if (packagedHaxelib.version !== semver.raw) {
        errors.push(`packaged haxelib.json version ${packagedHaxelib.version} does not match ${semver.raw}`)
      }
      const expectedNote = `v${semver.raw}: See CHANGELOG.md`
      if (packagedHaxelib.releasenote !== expectedNote) {
        errors.push(`packaged haxelib.json releasenote does not match ${semver.raw}`)
      }
      const packagedReadme = command('unzip', ['-p', assetPath, 'README.md'], root)
      const generatedReadme = state.updates.get('README.md')
      if (packagedReadme !== generatedReadme) {
        errors.push('packaged README.md does not match generated release state')
      }
    } catch (_error) {
      if (!errors.some((entry) => entry.startsWith('packaged '))) {
        errors.push(`release artifact dist/${assetName} does not contain readable release metadata`)
      }
    }
  }

  if (published) {
    try {
      const release = JSON.parse(
        command(
          'gh',
          ['release', 'view', tag, '--json', 'tagName,isDraft,isPrerelease,assets'],
          root
        )
      )
      if (release.tagName !== tag) {
        errors.push(`published GitHub Release tag ${release.tagName} does not match ${tag}`)
      }
      if (release.isDraft) {
        errors.push(`published GitHub Release ${tag} is still a draft`)
      }
      const expectedPrerelease = semver.raw.includes('-')
      if (Boolean(release.isPrerelease) !== expectedPrerelease) {
        errors.push(`published GitHub Release prerelease flag does not match ${semver.raw}`)
      }
      const assets = Array.isArray(release.assets) ? release.assets : []
      if (!assets.some((asset) => asset && asset.name === assetName)) {
        errors.push(`published GitHub Release is missing ${assetName}`)
      }
    } catch (error) {
      if (!errors.some((entry) => entry.includes('published GitHub Release'))) {
        errors.push(`published GitHub Release ${tag} could not be inspected`)
      }
    }
  }

  return [...new Set(errors)].sort()
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2))
    const errors = verifyReleaseState(args.root, args.version, {
      prepared: args.prepared,
      published: args.published
    })
    if (errors.length > 0) {
      console.error('[release-state] ERROR: release verification failed')
      for (const error of errors) console.error(`- ${error}`)
      process.exit(1)
    }
    const kind = args.prepared ? 'prepared ' : args.published ? 'published ' : ''
    console.log(`[release-state] verified ${kind}v${args.version}`)
  } catch (error) {
    console.error(`[release-state] ERROR: ${error.message}`)
    process.exit(1)
  }
}

if (require.main === module) {
  main()
}

module.exports = {
  verifyReleaseState
}
