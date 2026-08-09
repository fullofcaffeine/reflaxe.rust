const { GIT_OUTPUT_MAX_BYTES, gitObject } = require('./exact-git-source.js')

const PACKAGE_INPUT_ROOTS = ['scripts/ci', 'scripts/release', 'src', 'std', 'runtime', 'vendor']
const PACKAGE_INPUT_FILES = [
  'LICENSE',
  'README.md',
  'Run.hx',
  'docs/licenses/haxe-stdlib-4.3.7-MIT.txt',
  'docs/release-package-components.json',
  'docs/stdlib-provenance-ledger.json',
  'extraParams.hxml',
  'haxelib.json',
  'run.n'
]
const RELEASE_TOOL_FILES = [
  'scripts/ci/vendor-reflaxe-provenance.js',
  'scripts/release/deterministic-zip.js',
  'scripts/release/exact-git-source.js',
  'scripts/release/generate-license-artifacts.js',
  'scripts/release/haxelib-artifact-plugin.cjs',
  'scripts/release/package-haxelib.sh',
  'scripts/release/prepare-package-metadata.js',
  'scripts/release/published-verifier-plugin.cjs',
  'scripts/release/release-policy.js',
  'scripts/release/release-provenance.js',
  'scripts/release/reflaxe-metadata.js',
  'scripts/release/repair-release.js',
  'scripts/release/reviewed-source.js',
  'scripts/release/semantic-version.js',
  'scripts/release/verify-release-artifact.js'
]
function gitPaths(cwd, args) {
  return gitObject(cwd, ['ls-files', '-z', ...args])
    .toString('utf8')
    .split('\0')
    .filter(Boolean)
}

function trackedModes(cwd) {
  const output = gitObject(cwd, ['ls-files', '--stage', '-z']).toString('utf8')
  const result = new Map()
  for (const record of output.split('\0').filter(Boolean)) {
    const separator = record.indexOf('\t')
    if (separator < 0) continue
    const header = record.slice(0, separator)
    const mode = header.slice(0, 6)
    if (/^[0-9]{6}$/.test(mode)) result.set(record.slice(separator + 1), mode)
  }
  return result
}

function isReleaseInput(file) {
  return (
    PACKAGE_INPUT_FILES.includes(file) ||
    RELEASE_TOOL_FILES.includes(file) ||
    PACKAGE_INPUT_ROOTS.some((root) => file === root || file.startsWith(`${root}/`))
  )
}

/**
 * Why
 * Release archives are tied to one Git commit, but the package builder reads complete source,
 * runtime, standard-library, and vendor directories from the working tree. An untracked file in
 * one of those directories would otherwise enter the archive without belonging to that commit.
 *
 * What
 * Reject both ordinary untracked files and ignored files below every package input root.
 *
 * How
 * Ask Git for the two disjoint file sets, filter only paths the package builder consumes, and
 * report them in stable order. Untracked files elsewhere, such as a local `dist/` archive, do not
 * affect package contents and remain allowed.
 */
function assertPackageInputsTracked(cwd) {
  const candidates = [
    ...gitPaths(cwd, ['--others', '--exclude-standard']),
    ...gitPaths(cwd, ['--others', '--ignored', '--exclude-standard'])
  ]
  const unsafe = [...new Set(candidates)]
    .filter(isReleaseInput)
    .sort()
  if (unsafe.length > 0) {
    throw new Error(`release package input is not tracked by the source commit: ${unsafe.join(', ')}`)
  }
  const invalidModes = [...trackedModes(cwd)]
    .filter(([file, mode]) => isReleaseInput(file) && mode !== '100644' && mode !== '100755')
    .map(([file]) => file)
    .sort()
  if (invalidModes.length > 0) {
    throw new Error(
      `release package input must be a regular Git blob: ${invalidModes.join(', ')}`
    )
  }
}

module.exports = {
  assertPackageInputsTracked,
  isReleaseInput,
  GIT_OUTPUT_MAX_BYTES,
  PACKAGE_INPUT_FILES,
  PACKAGE_INPUT_ROOTS,
  RELEASE_TOOL_FILES
}
