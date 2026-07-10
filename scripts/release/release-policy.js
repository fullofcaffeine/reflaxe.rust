const fs = require('fs')
const path = require('path')
const semver = require('semver')

/**
 * Why
 * Release-line policy is project policy, while semantic-version parsing is a published standard.
 * Keeping those responsibilities separate avoids a custom parser becoming an accidental security
 * boundary and prevents tracked development metadata from influencing tag-derived version lineage.
 *
 * What
 * Load and validate the small release policy manifest, parse versions with the locked `semver`
 * package, and decide whether a fully derived release version is authorized.
 *
 * How
 * Major zero is always the initial-development line and maps breaking commits to a configured
 * non-major bump. Every major at or above one owns its own durable approval record. Prerelease and
 * build-metadata channels are rejected explicitly until the manifest grows a reviewed channel
 * model; they are not rejected by pretending they are invalid SemVer.
 */

function requireObject(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${label} must be an object`)
  }
  return value
}

function requireString(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`${label} must be a non-empty string`)
  }
  return value
}

function requireRealDate(value, label) {
  requireString(value, label)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new Error(`${label} must be a real YYYY-MM-DD date`)
  }
  const date = new Date(`${value}T00:00:00Z`)
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new Error(`${label} must be a real YYYY-MM-DD date`)
  }
  if (value > new Date().toISOString().slice(0, 10)) {
    throw new Error(`${label} must not be future-dated`)
  }
}

function validateApproval(approval, label) {
  if (approval === null) return
  requireObject(approval, label)
  requireString(approval.record, `${label}.record`)
  requireRealDate(approval.date, `${label}.date`)
}

function validateReleasePolicy(policy) {
  requireObject(policy, 'release policy')
  if (policy.schemaVersion !== 2) {
    throw new Error('release-manifest.json schemaVersion must be 2')
  }
  const lines = requireObject(policy.releaseLines, 'releaseLines')
  if (!Object.prototype.hasOwnProperty.call(lines, '0')) {
    throw new Error('releaseLines.0 is required')
  }

  for (const [major, value] of Object.entries(lines)) {
    if (!/^(0|[1-9][0-9]*)$/.test(major)) {
      throw new Error(`releaseLines contains invalid major ${major}`)
    }
    const line = requireObject(value, `releaseLines.${major}`)
    if (major === '0') {
      if (line.stage !== 'initial-development') {
        throw new Error('major 0 must use stage initial-development')
      }
      if (line.breakingBump !== 'minor') {
        throw new Error('releaseLines.0.breakingBump must be minor')
      }
      if (Object.prototype.hasOwnProperty.call(line, 'approval')) {
        throw new Error('releaseLines.0 must not define stable approval')
      }
      continue
    }

    if (line.stage !== 'stable') {
      throw new Error(`releaseLines.${major}.stage must be stable`)
    }
    if (!Object.prototype.hasOwnProperty.call(line, 'approval')) {
      throw new Error(`releaseLines.${major}.approval must be present (null until approved)`)
    }
    validateApproval(line.approval, `releaseLines.${major}.approval`)
  }

  return policy
}

function loadReleasePolicy(policyPath = path.resolve('release-manifest.json')) {
  let value
  try {
    value = JSON.parse(fs.readFileSync(policyPath, 'utf8'))
  } catch (error) {
    if (error instanceof SyntaxError) {
      throw new Error(`${policyPath}: invalid JSON`)
    }
    throw error
  }
  return validateReleasePolicy(value)
}

function parseSemanticVersion(version) {
  if (typeof version !== 'string') {
    throw new Error(`invalid semantic version: ${String(version)}`)
  }
  let parsed
  try {
    parsed = new semver.SemVer(version, { loose: false, includePrerelease: true })
  } catch (_error) {
    throw new Error(`invalid semantic version: ${version}`)
  }
  if (parsed.prerelease.length > 0) {
    throw new Error(`prerelease channels are not enabled: ${version}`)
  }
  if (parsed.build.length > 0) {
    throw new Error(`build metadata is not enabled: ${version}`)
  }
  return parsed
}

function releaseLine(policy, major) {
  const line = policy.releaseLines[String(major)]
  if (!line) throw new Error(`no release policy for major ${major}`)
  return line
}

function isStableMajorApproved(policy, major) {
  if (major < 1) return false
  const line = policy.releaseLines[String(major)]
  return Boolean(line && line.stage === 'stable' && line.approval)
}

function verifyReleaseVersion(policy, version) {
  const parsed = parseSemanticVersion(version)
  const line = releaseLine(policy, parsed.major)
  if (parsed.major === 0) return parsed
  if (line.stage !== 'stable' || line.approval === null) {
    throw new Error(`stable major ${parsed.major} requires an approved release record`)
  }
  return parsed
}

if (require.main === module) {
  try {
    const policy = loadReleasePolicy(path.resolve('release-manifest.json'))
    console.log(`[release-policy] OK: ${Object.keys(policy.releaseLines).length} configured release lines`)
  } catch (error) {
    console.error(`[release-policy] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = {
  isStableMajorApproved,
  loadReleasePolicy,
  parseSemanticVersion,
  releaseLine,
  validateReleasePolicy,
  verifyReleaseVersion
}
