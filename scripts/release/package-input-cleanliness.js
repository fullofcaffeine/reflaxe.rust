const { execFileSync } = require('child_process')

const PACKAGE_INPUT_ROOTS = ['src/', 'std/', 'runtime/', 'vendor/']
const OPTIONAL_PACKAGE_INPUT_FILES = ['Run.hx', 'run.n']

function gitPaths(cwd, args) {
  return execFileSync('git', ['ls-files', '-z', ...args], { cwd })
    .toString('utf8')
    .split('\0')
    .filter(Boolean)
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
    .filter(
      (file) =>
        OPTIONAL_PACKAGE_INPUT_FILES.includes(file) ||
        PACKAGE_INPUT_ROOTS.some((prefix) => file.startsWith(prefix))
    )
    .sort()
  if (unsafe.length > 0) {
    throw new Error(`release package input is not tracked by the source commit: ${unsafe.join(', ')}`)
  }
}

module.exports = { assertPackageInputsTracked, PACKAGE_INPUT_ROOTS, OPTIONAL_PACKAGE_INPUT_FILES }
