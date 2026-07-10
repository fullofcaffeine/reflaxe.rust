#!/usr/bin/env node

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const { strFromU8, unzipSync } = require('fflate')
const { compareEntryNames, validateEntryNames } = require('./deterministic-zip.js')

const REQUIRED_ENTRIES = [
  'LICENSE',
  'README.md',
  'extraParams.hxml',
  'haxelib.json',
  'release-metadata.json',
  'runtime/hxrt/Cargo.toml',
  'src/haxe/Exception.cross.hx',
  'src/reflaxe/rust/CompilerInit.hx',
  'vendor/reflaxe/src/reflaxe/ReflectCompiler.hx'
]
const ALLOWED_ROOT_FILES = new Set([
  'LICENSE',
  'README.md',
  'Run.hx',
  'extraParams.hxml',
  'haxelib.json',
  'release-metadata.json',
  'run.n'
])
const ALLOWED_ROOT_DIRECTORIES = new Set(['runtime', 'src', 'vendor'])

/**
 * Why
 * Correct metadata in two files does not prove that the published compiler package is complete or
 * safe. The exact ZIP approved before tagging must carry the compiler, runtime, vendored framework,
 * and source identity without traversal paths, duplicate names, symlinks, or development artifacts.
 *
 * What
 * Inspect the ZIP central directory before extraction, enforce the package layout contract, decode
 * exact metadata from the archive, and return the byte length and SHA-256 used by publication.
 *
 * How
 * A small central-directory reader exposes names, flags, methods, and Unix attributes that high-
 * level unzip maps normally hide. Only after structural validation succeeds is `fflate` used to
 * decode file contents.
 */

function findEndOfCentralDirectory(buffer) {
  const minimum = Math.max(0, buffer.length - 65_557)
  for (let offset = buffer.length - 22; offset >= minimum; offset -= 1) {
    if (buffer.readUInt32LE(offset) === 0x06054b50) return offset
  }
  throw new Error('invalid ZIP: end-of-central-directory record is missing')
}

function centralDirectoryEntries(buffer) {
  const end = findEndOfCentralDirectory(buffer)
  const count = buffer.readUInt16LE(end + 10)
  const centralSize = buffer.readUInt32LE(end + 12)
  let offset = buffer.readUInt32LE(end + 16)
  if (count === 0xffff || centralSize === 0xffffffff || offset === 0xffffffff) {
    throw new Error('ZIP64 release artifacts are not supported')
  }
  const expectedEnd = offset + centralSize
  const entries = []

  for (let index = 0; index < count; index += 1) {
    if (offset + 46 > buffer.length || buffer.readUInt32LE(offset) !== 0x02014b50) {
      throw new Error('invalid ZIP central directory')
    }
    const flags = buffer.readUInt16LE(offset + 8)
    const method = buffer.readUInt16LE(offset + 10)
    const nameLength = buffer.readUInt16LE(offset + 28)
    const extraLength = buffer.readUInt16LE(offset + 30)
    const commentLength = buffer.readUInt16LE(offset + 32)
    const externalAttributes = buffer.readUInt32LE(offset + 38)
    const nameStart = offset + 46
    const nameEnd = nameStart + nameLength
    const nameBytes = buffer.subarray(nameStart, nameEnd)
    const name = nameBytes.toString('utf8')
    if (!Buffer.from(name, 'utf8').equals(nameBytes)) throw new Error('archive entry name is not valid UTF-8')
    validateEntryNames([name])
    if ((flags & 0x1) !== 0) throw new Error(`encrypted archive entry is not allowed: ${name}`)
    if (method !== 0 && method !== 8) throw new Error(`unsupported ZIP compression method for ${name}`)
    const unixMode = externalAttributes >>> 16
    if ((unixMode & 0o170000) === 0o120000) throw new Error(`symbolic link entry is not allowed: ${name}`)
    if ((unixMode & 0o777) !== 0o644) throw new Error(`archive entry mode must be 0644: ${name}`)
    entries.push({ name, flags, method, unixMode })
    offset = nameEnd + extraLength + commentLength
  }
  if (offset !== expectedEnd) throw new Error('invalid ZIP central-directory size')
  validateEntryNames(entries.map(({ name }) => name))
  return entries
}

function parseJsonEntry(files, name) {
  try {
    return JSON.parse(strFromU8(files[name]))
  } catch (_error) {
    throw new Error(`archive entry is not readable JSON: ${name}`)
  }
}

function verifyLayout(names) {
  validateEntryNames(names)
  const sorted = [...names].sort(compareEntryNames)
  if (!names.every((name, index) => name === sorted[index])) {
    throw new Error('archive entries are not in canonical sorted order')
  }
  for (const required of REQUIRED_ENTRIES) {
    if (!names.includes(required)) throw new Error(`required archive entry is missing: ${required}`)
  }
  for (const name of names) {
    const [root, ...rest] = name.split('/')
    if (rest.length === 0) {
      if (!ALLOWED_ROOT_FILES.has(root)) throw new Error(`unexpected top-level archive entry: ${name}`)
    } else if (!ALLOWED_ROOT_DIRECTORIES.has(root)) {
      throw new Error(`unexpected archive root: ${root}`)
    }
    if (
      name.startsWith('std/') ||
      name.includes('/target/') ||
      name.includes('/node_modules/') ||
      name.includes('/.git/') ||
      name.startsWith('runtime/hxrt/tests/')
    ) {
      throw new Error(`development-only archive entry is not allowed: ${name}`)
    }
  }
}

function verifyReleaseArtifact({ zipPath, version, tag, sourceCommit }) {
  const bytes = fs.readFileSync(zipPath)
  const central = centralDirectoryEntries(bytes)
  const names = central.map(({ name }) => name)
  verifyLayout(names)

  let files
  try {
    files = unzipSync(bytes)
  } catch (_error) {
    throw new Error('release artifact cannot be decompressed')
  }
  const haxelib = parseJsonEntry(files, 'haxelib.json')
  if (haxelib.version !== version) {
    throw new Error(`packaged haxelib version ${String(haxelib.version)} does not match ${version}`)
  }
  if (haxelib.releasenote !== `v${version}: See GitHub Releases`) {
    throw new Error(`packaged haxelib releasenote does not match ${version}`)
  }
  if (haxelib.classPath !== 'src') throw new Error('packaged haxelib classPath must be src')
  if (Object.prototype.hasOwnProperty.call(haxelib, 'reflaxe')) {
    throw new Error('packaged haxelib metadata still contains the source-only reflaxe block')
  }

  const metadata = parseJsonEntry(files, 'release-metadata.json')
  if (metadata.schemaVersion !== 1) throw new Error('release metadata schemaVersion must be 1')
  if (metadata.version !== version) throw new Error('release metadata version does not match')
  if (metadata.tag !== tag) throw new Error('release metadata tag does not match')
  if (metadata.sourceCommit !== sourceCommit) throw new Error('release metadata source commit does not match')

  return {
    entries: names,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
    size: bytes.length
  }
}

function parseArgs(argv) {
  const values = {}
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index]
    const value = argv[index + 1]
    if (!flag || !flag.startsWith('--') || value === undefined) throw new Error('invalid verifier arguments')
    values[flag.slice(2)] = value
  }
  for (const required of ['zip', 'version', 'tag', 'source-sha']) {
    if (!values[required]) throw new Error(`--${required} is required`)
  }
  return values
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  const result = verifyReleaseArtifact({
    zipPath: path.resolve(args.zip),
    version: args.version,
    tag: args.tag,
    sourceCommit: args['source-sha']
  })
  console.log(JSON.stringify(result))
}

if (require.main === module) {
  try {
    main()
  } catch (error) {
    console.error(`[release-artifact] ERROR: ${error.message}`)
    process.exit(1)
  }
}

module.exports = { centralDirectoryEntries, verifyLayout, verifyReleaseArtifact }
