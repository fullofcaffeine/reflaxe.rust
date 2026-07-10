#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const { zipSync } = require('fflate')

// ZIP stores a timezone-free DOS date. Construct the same local wall-clock value in every process
// so changing `TZ` cannot change archive bytes.
const FIXED_MTIME = new Date(2000, 0, 1, 0, 0, 0)
const FILE_ATTRIBUTES = 0o644 << 16

function compareEntryNames(left, right) {
  return left < right ? -1 : left > right ? 1 : 0
}

/**
 * Why
 * A release artifact cannot be repaired or compared to its hosted copy if harmless filesystem
 * details produce different bytes. System `zip` commands normally preserve timestamps, modes, and
 * traversal order, making the same package content hash differently across builds.
 *
 * What
 * Create one canonical ZIP representation for a prepared package directory: sorted UTF-8 paths,
 * fixed timestamps, normalized file permissions, a pinned pure-JavaScript compressor, and no
 * symbolic links or special files.
 *
 * How
 * Walk with `lstat`, reject anything except directories and regular files, insert entries in sorted
 * order, and pass fixed ZIP metadata to the exactly locked `fflate` dependency.
 */

function validateEntryNames(names) {
  const seen = new Set()
  for (const name of names) {
    if (
      typeof name !== 'string' ||
      name.length === 0 ||
      name.includes('\0') ||
      name.includes('\\') ||
      name.startsWith('/') ||
      /^[A-Za-z]:/.test(name) ||
      name.endsWith('/') ||
      path.posix.normalize(name) !== name ||
      name.split('/').some((segment) => segment === '' || segment === '.' || segment === '..')
    ) {
      throw new Error(`unsafe archive entry: ${String(name)}`)
    }
    if (seen.has(name)) throw new Error(`duplicate archive entry: ${name}`)
    seen.add(name)
  }
  return [...names]
}

function collectFiles(root) {
  const files = []

  function visit(directory, segments) {
    const entries = fs
      .readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => compareEntryNames(left.name, right.name))
    for (const entry of entries) {
      const absolute = path.join(directory, entry.name)
      const nextSegments = [...segments, entry.name]
      const stat = fs.lstatSync(absolute)
      if (stat.isSymbolicLink()) {
        throw new Error(`symbolic link is not allowed in release archive: ${nextSegments.join('/')}`)
      }
      if (stat.isDirectory()) {
        visit(absolute, nextSegments)
        continue
      }
      if (!stat.isFile()) {
        throw new Error(`special file is not allowed in release archive: ${nextSegments.join('/')}`)
      }
      files.push({ absolute, name: nextSegments.join('/') })
    }
  }

  visit(root, [])
  files.sort((left, right) => compareEntryNames(left.name, right.name))
  validateEntryNames(files.map(({ name }) => name))
  return files
}

function createDeterministicZip(sourceDirectory, outputPath) {
  const root = path.resolve(sourceDirectory)
  const stat = fs.statSync(root)
  if (!stat.isDirectory()) throw new Error(`ZIP source is not a directory: ${sourceDirectory}`)

  const entries = Object.create(null)
  for (const file of collectFiles(root)) {
    Object.defineProperty(entries, file.name, {
      enumerable: true,
      value: [fs.readFileSync(file.absolute), { level: 9, mtime: FIXED_MTIME, os: 3, attrs: FILE_ATTRIBUTES }]
    })
  }

  const output = path.resolve(outputPath)
  fs.mkdirSync(path.dirname(output), { recursive: true })
  fs.writeFileSync(output, Buffer.from(zipSync(entries, { level: 9, mtime: FIXED_MTIME, os: 3, attrs: FILE_ATTRIBUTES })))
  return output
}

function main() {
  const [sourceDirectory, outputPath, ...rest] = process.argv.slice(2)
  if (!sourceDirectory || !outputPath || rest.length > 0) {
    throw new Error('usage: deterministic-zip.js <source-directory> <output.zip>')
  }
  createDeterministicZip(sourceDirectory, outputPath)
  console.log(`[deterministic-zip] wrote ${outputPath}`)
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[deterministic-zip] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = { collectFiles, compareEntryNames, createDeterministicZip, validateEntryNames }
