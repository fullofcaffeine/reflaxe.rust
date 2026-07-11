/**
 * Why
 * A release must identify the exact commit that passed CI. Publication therefore must not rewrite
 * tracked metadata, create a second commit, or make current documentation part of the transaction.
 *
 * What
 * Derive the version from real tags and Conventional Commits, apply the small manifest-owned
 * release-line policy, build one fixed-path Haxelib artifact, tag the tested commit, publish the
 * artifact plus checksum, and verify the hosted bytes.
 *
 * How
 * Project-local plugins own only policy, Haxelib artifact production, and provenance verification.
 * GitHub Release notes are canonical; no changelog or Git release commit plugin participates.
 */

module.exports = {
  branches: ['main'],
  tagFormat: 'v${version}',
  plugins: [
    ['./scripts/release/semantic-release-policy.cjs', { policyPath: 'release-manifest.json' }],
    [
      '@semantic-release/release-notes-generator',
      {
        // The locked `conventionalcommits` preset writer currently emits only a heading with the
        // release-notes generator. Keep its strict header grammar while using the generator's
        // proven default writer so feat/fix/perf and breaking entries remain visible.
        parserOpts: {
          headerPattern: /^(\w*)(?:\((.*)\))?!?: (.*)$/,
          breakingHeaderPattern: /^(\w*)(?:\((.*)\))?!: (.*)$/,
          headerCorrespondence: ['type', 'scope', 'subject'],
          noteKeywords: ['BREAKING CHANGE', 'BREAKING-CHANGE']
        }
      }
    ],
    './scripts/release/haxelib-artifact-plugin.cjs',
    [
      '@semantic-release/github',
      {
        successComment: false,
        failComment: false,
        releasedLabels: false,
        assets: [
          {
            path: 'dist/reflaxe.rust.zip',
            name: 'reflaxe.rust-${nextRelease.version}.zip',
            label: 'reflaxe.rust haxelib package'
          },
          {
            path: 'dist/reflaxe.rust.zip.sha256',
            name: 'reflaxe.rust-${nextRelease.version}.zip.sha256',
            label: 'SHA-256 checksum'
          }
        ]
      }
    ],
    './scripts/release/published-verifier-plugin.cjs'
  ]
}
