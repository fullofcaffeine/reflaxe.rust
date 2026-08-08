const path = require('path')
const {
  isStableMajorApproved,
  loadReleasePolicy,
  parseSemanticVersion,
  releaseLine,
  verifyReleaseVersion
} = require('./release-policy.js')

function policyPath(pluginConfig, context) {
  const configured = pluginConfig.policyPath || 'release-manifest.json'
  return path.isAbsolute(configured) ? configured : path.resolve(context.cwd, configured)
}

/**
 * Why
 * Conventional Commits correctly identifies consumer impact, but its default `major` result does
 * not express this project's deliberate initial-development policy. A breaking change on `0.x`
 * should advance the minor line until stable graduation has been explicitly approved.
 *
 * What
 * Delegate commit parsing to the pinned official analyzer, then apply one policy transformation:
 * cap a major result to the manifest's `0.x` breaking bump while major one remains unapproved.
 * The verify hook independently rejects unknown or unapproved derived majors.
 *
 * How
 * The plugin reads only tag-derived semantic-release context plus `release-manifest.json`. It never
 * reads package metadata, documentation, or another generated version surface.
 */
async function analyzeCommits(pluginConfig, context) {
  const { analyzeCommits: officialAnalyzeCommits } = await import('@semantic-release/commit-analyzer')
  const analyzed = await officialAnalyzeCommits(
    { preset: 'conventionalcommits', ...(pluginConfig.commitAnalyzer || {}) },
    context
  )
  if (analyzed !== 'major') return analyzed

  const lastVersion = context.lastRelease && context.lastRelease.version
  const last = parseSemanticVersion(lastVersion)
  const policy = loadReleasePolicy(policyPath(pluginConfig, context))
  if (last.major === 0 && !isStableMajorApproved(policy, 1)) {
    return releaseLine(policy, 0).breakingBump
  }
  return analyzed
}

async function verifyRelease(pluginConfig, context) {
  const policy = loadReleasePolicy(policyPath(pluginConfig, context))
  verifyReleaseVersion(policy, context.nextRelease.version)
  const expectedTag = `v${context.nextRelease.version}`
  if (
    context.nextRelease.gitTag !== expectedTag ||
    !/^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(expectedTag)
  ) {
    throw new Error('release tag must be the exact stable version selected by policy')
  }
  if (!/^[0-9a-f]{40}$/.test(context.env.RELEASE_SOURCE_COMMIT || '')) {
    throw new Error('release policy requires the exact reviewed source commit')
  }
  context.env.RELEASE_APPROVED_TAG = expectedTag
}

module.exports = { analyzeCommits, verifyRelease }
