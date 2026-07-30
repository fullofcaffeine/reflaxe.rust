const { execFileSync } = require('child_process')

const PACKAGE_INPUT_ROOTS = ['src/', 'std/', 'runtime/', 'vendor/']
const PACKAGE_INPUT_FILES = [
  'LICENSE',
  'README.md',
  'Run.hx',
  'docs/release-package-components.json',
  'docs/stdlib-provenance-ledger.json',
  'extraParams.hxml',
  'haxelib.json',
  'run.n'
]

function gitPaths(cwd, args) {
  return execFileSync('git', ['ls-files', '-z', ...args], { cwd })
    .toString('utf8')
    .split('\0')
    .filter(Boolean)
}

function trackedModes(cwd) {
  const output = execFileSync('git', ['ls-files', '--stage', '-z'], { cwd }).toString('utf8')
  const result = new Map()
  for (const record of output.split('\0').filter(Boolean)) {
    const match = /^([0-9]{6}) [0-9a-f]+ [0-9]+\t(.+)$/.exec(record)
    if (match) result.set(match[2], match[1])
  }
  return result
}

function isPackageInput(file) {
  return (
    PACKAGE_INPUT_FILES.includes(file) ||
    PACKAGE_INPUT_ROOTS.some((prefix) => file.startsWith(prefix))
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
    .filter(isPackageInput)
    .sort()
  if (unsafe.length > 0) {
    throw new Error(`release package input is not tracked by the source commit: ${unsafe.join(', ')}`)
  }
  const invalidModes = [...trackedModes(cwd)]
    .filter(([file, mode]) => isPackageInput(file) && mode !== '100644' && mode !== '100755')
    .map(([file]) => file)
    .sort()
  if (invalidModes.length > 0) {
    throw new Error(
      `release package input must be a regular Git blob: ${invalidModes.join(', ')}`
    )
  }
}

module.exports = { assertPackageInputsTracked, PACKAGE_INPUT_FILES, PACKAGE_INPUT_ROOTS }
