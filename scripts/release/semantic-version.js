const CORE_IDENTIFIER = '(0|[1-9][0-9]*)'
const PRERELEASE_IDENTIFIER = '(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)'
const BUILD_IDENTIFIER = '[0-9A-Za-z-]+'
const SEMANTIC_VERSION = new RegExp(
  `^${CORE_IDENTIFIER}\\.${CORE_IDENTIFIER}\\.${CORE_IDENTIFIER}` +
    `(?:-(${PRERELEASE_IDENTIFIER}(?:\\.${PRERELEASE_IDENTIFIER})*))?` +
    `(?:\\+(${BUILD_IDENTIFIER}(?:\\.${BUILD_IDENTIFIER})*))?$`
)

/**
 * Why
 * Package bytes must not depend on executable code loaded from `node_modules`. The release needs
 * only SemVer's closed syntax and numeric core, not range resolution or version selection.
 *
 * What
 * Parse one exact SemVer string into major, minor, patch, prerelease, and build fields.
 *
 * How
 * Enforce the SemVer 2.0.0 identifier grammar, reject unsafe JavaScript integers, and return a
 * small immutable record. Release-line policy separately decides whether prerelease/build channels
 * are allowed.
 */
function parseExactSemanticVersion(version) {
  if (typeof version !== 'string') {
    throw new Error(`invalid semantic version: ${String(version)}`)
  }
  const match = SEMANTIC_VERSION.exec(version)
  if (!match) throw new Error(`invalid semantic version: ${version}`)
  const numbers = match.slice(1, 4).map(Number)
  if (numbers.some((value) => !Number.isSafeInteger(value))) {
    throw new Error(`invalid semantic version: ${version}`)
  }
  return Object.freeze({
    major: numbers[0],
    minor: numbers[1],
    patch: numbers[2],
    prerelease: Object.freeze(match[4] ? match[4].split('.') : []),
    build: Object.freeze(match[5] ? match[5].split('.') : []),
    version
  })
}

module.exports = { parseExactSemanticVersion }
