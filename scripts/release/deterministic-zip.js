#!/usr/bin/env node

const fs = require('fs')
const path = require('path')
const { deflateRawSync } = require('zlib')

// ZIP stores a timezone-free DOS date. Construct the same local wall-clock value in every process
// so changing `TZ` cannot change archive bytes.
const FIXED_MTIME = new Date(2000, 0, 1, 0, 0, 0)
const DOS_TIME = 0
const DOS_DATE = ((FIXED_MTIME.getFullYear() - 1980) << 9) | ((FIXED_MTIME.getMonth() + 1) << 5) | FIXED_MTIME.getDate()
const FILE_ATTRIBUTES = 0o100644 * 0x10000
const UTF8_FLAG = 0x0800
const DEFLATE_METHOD = 8

const CRC32_TABLE = (() => {
  const table = new Uint32Array(256)
  for (let index = 0; index < table.length; index += 1) {
    let value = index
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value & 1) === 1 ? (value >>> 1) ^ 0xedb88320 : value >>> 1
    }
    table[index] = value >>> 0
  }
  return table
})()

function crc32(bytes) {
  let value = 0xffffffff
  for (const byte of bytes) value = CRC32_TABLE[(value ^ byte) & 0xff] ^ (value >>> 8)
  return (value ^ 0xffffffff) >>> 0
}

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
 * fixed timestamps, normalized file permissions, Node's pinned built-in DEFLATE implementation,
 * and no
 * symbolic links or special files.
 *
 * How
 * Walk with `lstat`, reject anything except directories and regular files, insert entries in sorted
 * order, write the small ZIP32 structure directly, and use built-in raw DEFLATE for file bytes.
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

function localHeader(entry) {
  const header = Buffer.alloc(30 + entry.name.length)
  header.writeUInt32LE(0x04034b50, 0)
  header.writeUInt16LE(20, 4)
  header.writeUInt16LE(UTF8_FLAG, 6)
  header.writeUInt16LE(DEFLATE_METHOD, 8)
  header.writeUInt16LE(DOS_TIME, 10)
  header.writeUInt16LE(DOS_DATE, 12)
  header.writeUInt32LE(entry.crc, 14)
  header.writeUInt32LE(entry.compressed.length, 18)
  header.writeUInt32LE(entry.bytes.length, 22)
  header.writeUInt16LE(entry.name.length, 26)
  header.writeUInt16LE(0, 28)
  entry.name.copy(header, 30)
  return header
}

function centralHeader(entry) {
  const header = Buffer.alloc(46 + entry.name.length)
  header.writeUInt32LE(0x02014b50, 0)
  header.writeUInt16LE((3 << 8) | 20, 4)
  header.writeUInt16LE(20, 6)
  header.writeUInt16LE(UTF8_FLAG, 8)
  header.writeUInt16LE(DEFLATE_METHOD, 10)
  header.writeUInt16LE(DOS_TIME, 12)
  header.writeUInt16LE(DOS_DATE, 14)
  header.writeUInt32LE(entry.crc, 16)
  header.writeUInt32LE(entry.compressed.length, 20)
  header.writeUInt32LE(entry.bytes.length, 24)
  header.writeUInt16LE(entry.name.length, 28)
  header.writeUInt16LE(0, 30)
  header.writeUInt16LE(0, 32)
  header.writeUInt16LE(0, 34)
  header.writeUInt16LE(0, 36)
  header.writeUInt32LE(FILE_ATTRIBUTES, 38)
  header.writeUInt32LE(entry.offset, 42)
  entry.name.copy(header, 46)
  return header
}

function endOfCentralDirectory(entryCount, centralSize, centralOffset) {
  const record = Buffer.alloc(22)
  record.writeUInt32LE(0x06054b50, 0)
  record.writeUInt16LE(0, 4)
  record.writeUInt16LE(0, 6)
  record.writeUInt16LE(entryCount, 8)
  record.writeUInt16LE(entryCount, 10)
  record.writeUInt32LE(centralSize, 12)
  record.writeUInt32LE(centralOffset, 16)
  record.writeUInt16LE(0, 20)
  return record
}

function zipBytes(sourceDirectory) {
  const files = collectFiles(sourceDirectory)
  if (files.length >= 0xffff) throw new Error('release archive has too many entries for canonical ZIP32')
  const entries = files.map((file) => {
    const bytes = fs.readFileSync(file.absolute)
    const name = Buffer.from(file.name, 'utf8')
    const compressed = deflateRawSync(bytes, { level: 9 })
    if (bytes.length >= 0xffffffff || compressed.length >= 0xffffffff) {
      throw new Error(`release archive entry is too large for canonical ZIP32: ${file.name}`)
    }
    return { bytes, compressed, crc: crc32(bytes), name, offset: 0 }
  })
  const local = []
  let offset = 0
  for (const entry of entries) {
    entry.offset = offset
    const header = localHeader(entry)
    local.push(header, entry.compressed)
    offset += header.length + entry.compressed.length
  }
  const central = entries.map(centralHeader)
  const centralSize = central.reduce((total, entry) => total + entry.length, 0)
  if (offset >= 0xffffffff || centralSize >= 0xffffffff) {
    throw new Error('release archive is too large for canonical ZIP32')
  }
  return Buffer.concat([
    ...local,
    ...central,
    endOfCentralDirectory(entries.length, centralSize, offset)
  ])
}

function createDeterministicZip(sourceDirectory, outputPath) {
  const root = path.resolve(sourceDirectory)
  const stat = fs.statSync(root)
  if (!stat.isDirectory()) throw new Error(`ZIP source is not a directory: ${sourceDirectory}`)

  const output = path.resolve(outputPath)
  fs.mkdirSync(path.dirname(output), { recursive: true })
  fs.writeFileSync(output, zipBytes(root))
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

module.exports = { collectFiles, compareEntryNames, crc32, createDeterministicZip, validateEntryNames, zipBytes }
