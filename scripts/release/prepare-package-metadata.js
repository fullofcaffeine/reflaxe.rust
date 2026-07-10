#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const semver = require('semver')

/**
 * Why
 * Exact release versions belong to the distributable, while the checkout must remain the exact
 * source commit that passed CI. Writing metadata only inside package staging preserves both facts.
 *
 * What
 * Update the staged `haxelib.json` version/release note and write the package-local provenance
 * record that binds the artifact to its version, tag, and source commit.
 *
 * How
 * Accept explicit paths supplied by the package adapter, validate all boundary values, and write
 * deterministic JSON with a final newline. No tracked repository file is touched.
 */

function preparePackageMetadata({ haxelibPath, metadataPath, version, tag, sourceCommit }) {
  if (semver.valid(version, { loose: false }) === null) {
    throw new Error(`invalid package semantic version: ${version}`)
  }
  if (typeof tag !== 'string' || tag.length === 0) throw new Error('package tag is required')
  if (!/^[0-9a-f]{40}$/i.test(sourceCommit)) throw new Error('source commit must be a 40-character Git SHA')

  const haxelib = JSON.parse(fs.readFileSync(haxelibPath, 'utf8'))
  haxelib.version = version
  haxelib.releasenote = `v${version}: See GitHub Releases`
  fs.writeFileSync(haxelibPath, `${JSON.stringify(haxelib, null, 2)}\n`)

  const metadata = {
    schemaVersion: 1,
    version,
    tag,
    sourceCommit: sourceCommit.toLowerCase()
  }
  fs.mkdirSync(path.dirname(metadataPath), { recursive: true })
  fs.writeFileSync(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`)
}

function main() {
  const [haxelibPath, metadataPath, version, tag, sourceCommit, ...rest] = process.argv.slice(2)
  if (!haxelibPath || !metadataPath || !version || !tag || !sourceCommit || rest.length > 0) {
    throw new Error(
      'usage: prepare-package-metadata.js <staged-haxelib.json> <release-metadata.json> <version> <tag> <source-sha>'
    )
  }
  preparePackageMetadata({ haxelibPath, metadataPath, version, tag, sourceCommit })
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[package-metadata] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = { preparePackageMetadata }
