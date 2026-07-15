#!/usr/bin/env node

const childProcess = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const rootDir = path.resolve(__dirname, '../..')
const installerPath = path.join(rootDir, 'scripts/install-git-hooks.sh')
const trackedHookPath = path.join(rootDir, 'scripts/hooks/pre-commit')
const trackedHook = fs.readFileSync(trackedHookPath, 'utf8')
const templateInstallerPath = path.join(rootDir, 'templates/basic/scripts/install-git-hooks.sh')
const templateHookPath = path.join(rootDir, 'templates/basic/scripts/hooks/pre-commit')

if (trackedHook.includes('bd hooks run pre-commit')) {
  throw new Error('tracked repository validation must not recursively invoke the Beads hook runner')
}
if (!fs.readFileSync(installerPath).equals(fs.readFileSync(templateInstallerPath))) {
  throw new Error('generated-project hook installer is stale; run npm run hooks:sync-template')
}
const templateHook = fs.readFileSync(templateHookPath, 'utf8')
if (templateHook.includes('bd hooks run pre-commit')) {
  throw new Error('generated-project validation must not recursively invoke the Beads hook runner')
}
if (!templateHook.includes('# --- END REFLAXE.RUST REPOSITORY PRE-COMMIT ---')) {
  throw new Error('generated-project hook is missing the explicit repository boundary')
}

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-hook-installation-'))

function cleanup() {
  fs.rmSync(tempDir, { recursive: true, force: true })
}

function writeExecutable(filePath, contents) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, contents)
  fs.chmodSync(filePath, 0o755)
}

function run(command, args, env = {}) {
  return childProcess.execFileSync(command, args, {
    cwd: tempDir,
    env: { ...process.env, ...env },
    encoding: 'utf8',
    timeout: 10_000,
  })
}

try {
  run('git', ['init', '-q'])
  fs.mkdirSync(path.join(tempDir, '.beads'), { recursive: true })
  fs.mkdirSync(path.join(tempDir, 'scripts/hooks'), { recursive: true })
  fs.copyFileSync(installerPath, path.join(tempDir, 'scripts/install-git-hooks.sh'))

  const fixtureHook = `#!/usr/bin/env bash
set -euo pipefail

printf 'repo\\n' >> "$REPO_HOOK_COUNT_FILE"

# --- END REFLAXE.RUST REPOSITORY PRE-COMMIT ---
`
  writeExecutable(path.join(tempDir, 'scripts/hooks/pre-commit'), fixtureHook)

  const legacyRecursiveHook = `#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(git rev-parse --show-toplevel)"
installed_repo_hook="$ROOT_DIR/.git/hooks/pre-commit.old"
echo "[pre-commit] Running local path guard on staged changes..."
bash "$ROOT_DIR/scripts/lint/local_path_guard_staged.sh"
bash "$ROOT_DIR/scripts/security/run-gitleaks.sh" --staged
bd hooks run pre-commit
echo "[pre-commit] OK"
`
  writeExecutable(path.join(tempDir, '.git/hooks/pre-commit'), legacyRecursiveHook)
  writeExecutable(path.join(tempDir, '.git/hooks/pre-commit.old'), legacyRecursiveHook)

  const fakeBin = path.join(tempDir, 'fake-bin')
  const fakeBd = `#!/usr/bin/env bash
set -euo pipefail

if [[ "$1 $2 $3" == "hooks install --chain" ]]; then
  hook_path="$PWD/.git/hooks/pre-commit"
  if ! grep -q '^# --- BEGIN BEADS INTEGRATION ' "$hook_path"; then
    cat >> "$hook_path" <<'BEADS'

# --- BEGIN BEADS INTEGRATION v-test ---
if command -v bd >/dev/null 2>&1; then
  bd hooks run pre-commit "$@"
fi
# --- END BEADS INTEGRATION v-test ---
BEADS
  fi
  exit 0
fi

if [[ "$1 $2" == "hooks run" && "$3" == "pre-commit" ]]; then
  printf 'beads\\n' >> "$BEADS_HOOK_COUNT_FILE"
  if [[ -x "$PWD/.git/hooks/pre-commit.old" ]]; then
    "$PWD/.git/hooks/pre-commit.old"
  fi
  exit 0
fi

echo "unexpected fake bd invocation: $*" >&2
exit 64
`
  writeExecutable(path.join(fakeBin, 'bd'), fakeBd)

  const installEnv = { PATH: `${fakeBin}${path.delimiter}${process.env.PATH}` }
  run('bash', ['scripts/install-git-hooks.sh'], installEnv)
  const installedPath = path.join(tempDir, '.git/hooks/pre-commit')
  const firstInstall = fs.readFileSync(installedPath)

  run('bash', ['scripts/install-git-hooks.sh'], installEnv)
  const secondInstall = fs.readFileSync(installedPath)
  if (!firstInstall.equals(secondInstall)) {
    throw new Error('two consecutive hook installs must be byte-identical')
  }

  if (fs.existsSync(path.join(tempDir, '.git/hooks/pre-commit.old'))) {
    throw new Error('installer must remove the recognized legacy repository-hook chain')
  }

  const installed = secondInstall.toString('utf8')
  const integrationCount = installed.split('# --- BEGIN BEADS INTEGRATION ').length - 1
  if (integrationCount !== 1) {
    throw new Error(`expected one Beads integration section, found ${integrationCount}`)
  }
  const repositoryBoundaryCount = installed.split('# --- END REFLAXE.RUST REPOSITORY PRE-COMMIT ---').length - 1
  if (repositoryBoundaryCount !== 1) {
    throw new Error(`expected one repository-hook boundary, found ${repositoryBoundaryCount}`)
  }

  const repoCountPath = path.join(tempDir, 'repo-count.txt')
  const beadsCountPath = path.join(tempDir, 'beads-count.txt')
  run(installedPath, [], {
    ...installEnv,
    REPO_HOOK_COUNT_FILE: repoCountPath,
    BEADS_HOOK_COUNT_FILE: beadsCountPath,
  })

  const repoRuns = fs.readFileSync(repoCountPath, 'utf8').trim().split('\n')
  const beadsRuns = fs.readFileSync(beadsCountPath, 'utf8').trim().split('\n')
  if (repoRuns.length !== 1 || repoRuns[0] !== 'repo') {
    throw new Error(`repository validation must run exactly once, got ${repoRuns.length}`)
  }
  if (beadsRuns.length !== 1 || beadsRuns[0] !== 'beads') {
    throw new Error(`Beads validation must run exactly once, got ${beadsRuns.length}`)
  }

  console.log('[git-hook-installation-test] OK')
} finally {
  cleanup()
}
