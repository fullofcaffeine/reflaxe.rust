/**
 * Why
 * The release commit must contain every file generated from `release-manifest.json`. Repeating
 * that list in static semantic-release configuration would recreate the synchronization defect
 * this release architecture exists to remove.
 *
 * What
 * Configure semantic-release with two explicit phases around its release commit: generate/package
 * before the commit, then verify the prepared commit before semantic-release creates its tag.
 * Derive the release-commit assets directly from the same generator that owns release state.
 *
 * How
 * `releaseCommitFiles` renders the current manifest contract in memory and returns all generated
 * paths plus the manifest and changelog. The publish phase rechecks the tag, and the success phase
 * verifies the GitHub Release and zip asset.
 */

const { releaseCommitFiles } = require('./scripts/release/sync-versions.js')

module.exports = {
  branches: ['main'],
  plugins: [
    '@semantic-release/commit-analyzer',
    '@semantic-release/release-notes-generator',
    '@semantic-release/changelog',
    [
      '@semantic-release/exec',
      {
        prepareCmd: 'node scripts/release/sync-versions.js ${nextRelease.version} && (rm -f dist/*.zip 2>/dev/null || true) && bash scripts/release/package-haxelib.sh dist/reflaxe.rust-${nextRelease.version}.zip'
      }
    ],
    [
      '@semantic-release/git',
      {
        assets: releaseCommitFiles(__dirname),
        message: 'chore(release): ${nextRelease.version}\n\n${nextRelease.notes}'
      }
    ],
    [
      '@semantic-release/exec',
      {
        prepareCmd: 'node scripts/release/verify-release-state.js ${nextRelease.version} --prepared',
        publishCmd: 'node scripts/release/verify-release-state.js ${nextRelease.version}',
        successCmd: 'node scripts/release/verify-release-state.js ${nextRelease.version} --published'
      }
    ],
    [
      '@semantic-release/github',
      {
        assets: [
          {
            path: 'dist/*.zip',
            label: 'reflaxe.rust haxelib package'
          }
        ]
      }
    ]
  ]
}
