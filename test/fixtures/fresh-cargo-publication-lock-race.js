#!/usr/bin/env node

const cp = require('child_process')
const fs = require('fs')
const path = require('path')

const apiPath = process.argv[2]
const root = process.argv[3]
const role = process.argv[4]
const barrier = `${root}.barrier`
const critical = `${root}.critical`

function waitFor(predicate, timeoutMs = 10000) {
  const deadline = Date.now() + timeoutMs
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error('timed out while reproducing the stale-lock race')
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 10)
  }
}

if (role != null) {
  const stalePid = 2147483647
  const originalKill = process.kill
  let observed = false
  process.kill = (pid, signal) => {
    if (pid !== stalePid || observed) return originalKill(pid, signal)
    observed = true
    fs.writeFileSync(path.join(barrier, role), `${process.pid}\n`)
    waitFor(() => fs.existsSync(path.join(barrier, role === 'a' ? 'b' : 'a')))
    const error = new Error('no such process')
    error.code = 'ESRCH'
    throw error
  }
  const api = require(apiPath)
  const lock = api.acquirePublicationLock(root)
  let marker = null
  try {
    marker = fs.openSync(critical, 'wx')
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 150)
  } finally {
    if (marker != null) {
      fs.closeSync(marker)
      fs.rmSync(critical)
    }
    api.releasePublicationLock(lock)
  }
  process.exit(0)
}

fs.mkdirSync(barrier, { recursive: true })
const api = require(apiPath)
const paths = api.publicationPaths(root)
fs.writeFileSync(paths.lock, `${JSON.stringify({ schemaVersion: 1, pid: 2147483647 }, null, 2)}\n`)
const children = ['a', 'b'].map((childRole) => cp.spawn(
  process.execPath,
  [__filename, apiPath, root, childRole],
  { stdio: ['ignore', 'pipe', 'pipe'] }
))
Promise.all(children.map((child) => new Promise((resolve, reject) => {
  let output = ''
  child.stdout.on('data', (chunk) => { output += chunk })
  child.stderr.on('data', (chunk) => { output += chunk })
  child.on('error', reject)
  child.on('exit', (code) => code === 0 ? resolve() : reject(new Error(output || `child exited ${code}`)))
}))).then(() => {
  if (fs.existsSync(critical)) throw new Error('critical-section marker remains after lock race')
  process.stdout.write('stale-lock race serialized\n')
}).catch((error) => {
  console.error(error.stack || error.message)
  process.exitCode = 1
})
