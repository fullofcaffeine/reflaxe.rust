#!/usr/bin/env node

/**
 * Why
 * Version metadata and public release posture are one release-state contract. Updating package
 * files separately from status prose previously allowed an untagged `1.0.0` metadata edit to drift
 * back to the real `0.x` tag lineage while current-facing docs continued claiming a stable line.
 *
 * What
 * Read `release-manifest.json`, select the policy for the requested semantic-version major, and
 * generate every mechanically derived version field plus each marker-delimited current-posture
 * block. Stable-line generation is rejected until the manifest carries an explicit graduation
 * approval record.
 *
 * How
 * Write mode is used by semantic-release prepare. `--check` renders the same outputs in memory and
 * compares them byte-for-byte for local/CI validation. `--root` supports isolated deterministic
 * fixtures. No network or Git state participates in generation.
 *
 * Usage
 *   node scripts/release/sync-versions.js 0.82.0
 *   node scripts/release/sync-versions.js --check
 */

const fs = require('fs')
const path = require('path')

const MANIFEST_PATH = 'release-manifest.json'
const POSTURE_START = '<!-- GENERATED:release-posture:start -->'
const POSTURE_END = '<!-- GENERATED:release-posture:end -->'
const SEMVER_PATTERN = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?$/

function parseArgs(argv) {
  let root = process.cwd()
  let check = false
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
    if (arg === '--check') {
      check = true
      continue
    }
    if (arg.startsWith('--')) {
      throw new Error(`unknown argument: ${arg}`)
    }
    if (version !== null) {
      throw new Error(`unexpected extra version argument: ${arg}`)
    }
    version = arg
  }

  return { root, check, version }
}

function absolute(root, relativePath) {
  return path.resolve(root, relativePath)
}

function readText(root, relativePath) {
  const filePath = absolute(root, relativePath)
  if (!fs.existsSync(filePath)) {
    throw new Error(`${relativePath}: required file is missing`)
  }
  return fs.readFileSync(filePath, 'utf8')
}

function readJson(root, relativePath) {
  try {
    return JSON.parse(readText(root, relativePath))
  } catch (error) {
    if (error instanceof SyntaxError) {
      throw new Error(`${relativePath}: invalid JSON`)
    }
    throw error
  }
}

function jsonText(value) {
  return `${JSON.stringify(value, null, 2)}\n`
}

function parseSemver(version) {
  if (typeof version !== 'string') {
    throw new Error('version must be a string')
  }
  const match = version.match(SEMVER_PATTERN)
  if (!match) {
    throw new Error(`invalid semver: ${version}`)
  }
  return {
    raw: version,
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3])
  }
}

function requireString(value, label) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`${MANIFEST_PATH}: ${label} must be a non-empty string`)
  }
  return value
}

function requireIsoDate(value, label) {
  requireString(value, label)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${MANIFEST_PATH}: ${label} must use YYYY-MM-DD`)
  }
  const parsed = new Date(`${value}T00:00:00Z`)
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    throw new Error(`${MANIFEST_PATH}: ${label} must be a real calendar date`)
  }
}

function requireSafeRelativePath(value, label) {
  requireString(value, label)
  const segments = value.split(/[\\/]/)
  if (path.isAbsolute(value) || segments.includes('..') || segments.includes('.')) {
    throw new Error(`${MANIFEST_PATH}: ${label} must be a normalized repository-relative path`)
  }
}

function validateManifest(manifest) {
  if (manifest.schemaVersion !== 1) {
    throw new Error(`${MANIFEST_PATH}: schemaVersion must be 1`)
  }
  requireSafeRelativePath(manifest.canonicalDocument, 'canonicalDocument')

  const graduation = manifest.stableGraduation
  if (!graduation || !Number.isInteger(graduation.major) || graduation.major < 1) {
    throw new Error(`${MANIFEST_PATH}: stableGraduation.major must be an integer >= 1`)
  }
  if (typeof graduation.approved !== 'boolean') {
    throw new Error(`${MANIFEST_PATH}: stableGraduation.approved must be boolean`)
  }
  if (graduation.approved) {
    requireString(graduation.approvalBead, 'stableGraduation.approvalBead')
    requireIsoDate(graduation.approvalDate, 'stableGraduation.approvalDate')
  } else if (graduation.approvalBead !== null || graduation.approvalDate !== null) {
    throw new Error(
      `${MANIFEST_PATH}: unapproved stableGraduation must use null approvalBead and approvalDate`
    )
  }

  if (!manifest.releaseLines || typeof manifest.releaseLines !== 'object') {
    throw new Error(`${MANIFEST_PATH}: releaseLines must be an object`)
  }
  for (const [major, line] of Object.entries(manifest.releaseLines)) {
    if (!/^(0|[1-9][0-9]*)$/.test(major)) {
      throw new Error(`${MANIFEST_PATH}: invalid releaseLines major '${major}'`)
    }
    requireString(line.channel, `releaseLines.${major}.channel`)
    requireString(line.status, `releaseLines.${major}.status`)
    requireString(line.maturity, `releaseLines.${major}.maturity`)
    if (
      Object.prototype.hasOwnProperty.call(line, 'requiresGraduationApproval') &&
      typeof line.requiresGraduationApproval !== 'boolean'
    ) {
      throw new Error(`${MANIFEST_PATH}: releaseLines.${major}.requiresGraduationApproval must be boolean`)
    }
  }
  const stableLine = manifest.releaseLines[String(graduation.major)]
  if (!stableLine) {
    throw new Error(
      `${MANIFEST_PATH}: releaseLines.${graduation.major} must define the graduation major`
    )
  }
  for (const [major, line] of Object.entries(manifest.releaseLines)) {
    if (Number(major) >= 1 && line.requiresGraduationApproval !== true) {
      throw new Error(`${MANIFEST_PATH}: releaseLines.${major} must require graduation approval`)
    }
  }
  if (!Array.isArray(manifest.generatedPostureFiles) || manifest.generatedPostureFiles.length === 0) {
    throw new Error(`${MANIFEST_PATH}: generatedPostureFiles must be a non-empty array`)
  }
  const seen = new Set()
  for (const [index, entry] of manifest.generatedPostureFiles.entries()) {
    if (!entry || typeof entry !== 'object') {
      throw new Error(`${MANIFEST_PATH}: generatedPostureFiles.${index} must be an object`)
    }
    requireSafeRelativePath(entry.path, `generatedPostureFiles.${index}.path`)
    requireString(entry.canonicalLink, `generatedPostureFiles.${index}.canonicalLink`)
    if (seen.has(entry.path)) {
      throw new Error(`${MANIFEST_PATH}: duplicate generated posture path ${entry.path}`)
    }
    seen.add(entry.path)
  }

  if (!seen.has(manifest.canonicalDocument)) {
    throw new Error(`${MANIFEST_PATH}: canonicalDocument must be generated by generatedPostureFiles`)
  }
}

function selectReleaseLine(manifest, semver) {
  const line = manifest.releaseLines[String(semver.major)]
  if (!line) {
    throw new Error(`${MANIFEST_PATH}: no release policy for major ${semver.major}`)
  }
  if (line.requiresGraduationApproval) {
    const graduation = manifest.stableGraduation
    if (
      graduation.major !== semver.major ||
      !graduation.approved ||
      typeof graduation.approvalBead !== 'string' ||
      graduation.approvalBead.length === 0 ||
      typeof graduation.approvalDate !== 'string' ||
      graduation.approvalDate.length === 0
    ) {
      throw new Error(
        `stable ${semver.major}.x generation requires an approved graduation record in ${MANIFEST_PATH}`
      )
    }
  }
  return line
}

function replaceGeneratedBlock(original, relativePath, replacement) {
  const startIndex = original.indexOf(POSTURE_START)
  const endIndex = original.indexOf(POSTURE_END)
  if (startIndex === -1 || endIndex === -1 || endIndex <= startIndex) {
    throw new Error(`${relativePath}: missing release-posture generated markers`)
  }
  if (
    original.indexOf(POSTURE_START, startIndex + POSTURE_START.length) !== -1 ||
    original.indexOf(POSTURE_END, endIndex + POSTURE_END.length) !== -1
  ) {
    throw new Error(`${relativePath}: duplicate release-posture generated markers`)
  }
  const before = original.slice(0, startIndex)
  const after = original.slice(endIndex + POSTURE_END.length)
  return `${before}${replacement}${after}`
}

function renderPostureBlock(entry, semver, line) {
  return [
    POSTURE_START,
    `Current release posture: **${line.status}**.`,
    '',
    `Maturity: **${line.maturity}**. See [Semver And Release Posture](${entry.canonicalLink}).`,
    POSTURE_END
  ].join('\n')
}

function buildReleaseState(root, version) {
  const semver = parseSemver(version)
  const manifest = readJson(root, MANIFEST_PATH)
  validateManifest(manifest)
  const line = selectReleaseLine(manifest, semver)
  const updates = new Map()

  function current(relativePath) {
    return updates.has(relativePath) ? updates.get(relativePath) : readText(root, relativePath)
  }

  function updateJson(relativePath, mutate) {
    const value = JSON.parse(current(relativePath))
    mutate(value)
    updates.set(relativePath, jsonText(value))
  }

  updateJson('package.json', (json) => {
    json.version = semver.raw
  })
  updateJson('package-lock.json', (json) => {
    json.version = semver.raw
    if (!json.packages || !json.packages['']) {
      throw new Error('package-lock.json: missing root package metadata')
    }
    json.packages[''].version = semver.raw
  })
  updateJson('haxelib.json', (json) => {
    json.version = semver.raw
    json.releasenote = `v${semver.raw}: See CHANGELOG.md`
  })

  const hxmlPath = 'haxe_libraries/reflaxe.rust.hxml'
  const hxml = current(hxmlPath)
  const hxmlPattern = /^-D\s+reflaxe\.rust=[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?\s*$/m
  if (!hxmlPattern.test(hxml)) {
    throw new Error(`${hxmlPath}: no reflaxe.rust version define found`)
  }
  updates.set(hxmlPath, hxml.replace(hxmlPattern, `-D reflaxe.rust=${semver.raw}`))

  const readmePath = 'README.md'
  const readmeBadgePattern = /\[!\[Version\]\(https:\/\/img\.shields\.io\/badge\/version-[0-9A-Za-z.-]+-blue\)\]/
  const readme = current(readmePath)
  if (!readmeBadgePattern.test(readme)) {
    throw new Error(`${readmePath}: version badge not found`)
  }
  updates.set(
    readmePath,
    readme.replace(
      readmeBadgePattern,
      `[![Version](https://img.shields.io/badge/version-${semver.raw}-blue)]`
    )
  )

  for (const entry of manifest.generatedPostureFiles) {
    const original = current(entry.path)
    const rendered = renderPostureBlock(entry, semver, line)
    updates.set(entry.path, replaceGeneratedBlock(original, entry.path, rendered))
  }

  return { manifest, semver, line, updates }
}

function staleGeneratedFiles(root, state) {
  return [...state.updates.entries()]
    .filter(([relativePath, expected]) => readText(root, relativePath) !== expected)
    .map(([relativePath]) => relativePath)
    .sort()
}

function writeReleaseState(root, state) {
  for (const [relativePath, content] of state.updates.entries()) {
    const filePath = absolute(root, relativePath)
    if (fs.readFileSync(filePath, 'utf8') !== content) {
      fs.writeFileSync(filePath, content)
    }
  }
}

function resolveVersion(root, requestedVersion) {
  if (requestedVersion !== null) {
    return requestedVersion
  }
  const packageJson = readJson(root, 'package.json')
  return packageJson.version
}

function releaseCommitFiles(root) {
  const version = resolveVersion(root, null)
  const state = buildReleaseState(root, version)
  return [
    ...state.updates.keys(),
    MANIFEST_PATH,
    'CHANGELOG.md'
  ].sort()
}

function main() {
  let args
  try {
    args = parseArgs(process.argv.slice(2))
    if (!args.check && args.version === null) {
      throw new Error('write mode requires a version argument')
    }
    const version = resolveVersion(args.root, args.version)
    const state = buildReleaseState(args.root, version)
    if (args.check) {
      const stale = staleGeneratedFiles(args.root, state)
      if (stale.length > 0) {
        console.error('[release-state] ERROR: generated release state is stale')
        for (const relativePath of stale) {
          console.error(`- ${relativePath}: generated release state is stale`)
        }
        process.exit(1)
      }
      console.log(`[release-state] OK: ${state.semver.raw} (${state.line.channel})`)
      return
    }

    writeReleaseState(args.root, state)
    console.log(`[release-state] synced ${state.semver.raw} (${state.line.channel})`)
  } catch (error) {
    console.error(`[release-state] ERROR: ${error.message}`)
    process.exit(1)
  }
}

if (require.main === module) {
  main()
}

module.exports = {
  buildReleaseState,
  parseSemver,
  releaseCommitFiles,
  staleGeneratedFiles
}
