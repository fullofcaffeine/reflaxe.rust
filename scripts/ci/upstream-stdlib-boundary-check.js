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

const approvedStdOverrideRoots = ['std/']
const trackedVendor = gitTrackedUnder('vendor/haxe')

if (trackedVendor.length > 0) {
  fail(
    `tracked files under vendor/haxe are not allowed. Keep upstream vendor roots untracked and sync required overrides into ${approvedStdOverrideRoots.join(
      ', '
    )}. Found:\n${summarize(trackedVendor, 20)}`
  )
}

const trackedStd = gitTrackedUnder('std')
const allowedStdFiles = trackedStd.filter((path) => {
  if (path === 'std/AGENTS.md') return true
  return (
    path.endsWith('.hx') ||
    path.endsWith('.cross.hx') ||
    path.endsWith('.rs')
  )
})

if (allowedStdFiles.length !== trackedStd.length) {
  const disallowed = trackedStd.filter((path) => !allowedStdFiles.includes(path))
  fail(
    `stdlib override roots may only contain .hx/.cross.hx/.rs files (plus std/AGENTS.md). Found:\n${summarize(disallowed, 20)}`
  )
}

console.log(
  `[ci:guards] OK: upstream stdlib boundary (vendor/haxe untracked; approved override roots: ${approvedStdOverrideRoots.join(', ')})`
)

if (process.exitCode) process.exit(process.exitCode)
