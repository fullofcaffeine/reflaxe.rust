#!/usr/bin/env node

const cp = require('child_process')

function fail(msg) {
  console.error(`[ci:guards] ERROR: ${msg}`)
  process.exitCode = 1
}

function gitTrackedUnder(path) {
  try {
    const out = cp.execFileSync('git', ['ls-files', '-z', '--', path], { encoding: 'utf8' })
    return out.split('\0').filter(Boolean)
  } catch (_) {
    return []
  }
}

function summarize(paths, limit) {
  const slice = paths.slice(0, limit).map((path) => `- ${path}`)
  const suffix = paths.length > limit ? `\n- ... (${paths.length - limit} more)` : ''
  return `${slice.join('\n')}${suffix}`
}

const approvedStdOverrideRoots = ['std/', 'std/rust/_std/']
const trackedVendor = gitTrackedUnder('vendor/haxe')

if (trackedVendor.length > 0) {
  fail(
    `tracked files under vendor/haxe are not allowed. Keep upstream vendor roots untracked and sync required overrides into ${approvedStdOverrideRoots.join(
      ', '
    )}. Found:\n${summarize(trackedVendor, 20)}`
  )
}

const trackedStd = gitTrackedUnder('std')
const sourceCrossFiles = trackedStd.filter((path) => path.endsWith('.cross.hx'))
const allowedStdFiles = trackedStd.filter((path) => {
  if (path === 'std/AGENTS.md') return true
  return (
    path.endsWith('.hx') ||
    path.endsWith('.rs')
  )
})

if (sourceCrossFiles.length > 0) {
  fail(
    `checked-in std sources must not use .cross.hx; Reflaxe build generates packaged .cross.hx files from std/rust/_std/**/*.hx. Found:\n${summarize(sourceCrossFiles, 20)}`
  )
}

if (allowedStdFiles.length !== trackedStd.length) {
  const disallowed = trackedStd.filter((path) => !allowedStdFiles.includes(path))
  fail(
    `stdlib override roots may only contain .hx/.rs files (plus std/AGENTS.md). Found:\n${summarize(disallowed, 20)}`
  )
}

console.log(
  `[ci:guards] OK: upstream stdlib boundary (vendor/haxe untracked; checked-in std sources use .hx/.rs; approved override roots: ${approvedStdOverrideRoots.join(', ')})`
)

if (process.exitCode) process.exit(process.exitCode)
