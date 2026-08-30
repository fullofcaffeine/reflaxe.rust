#!/usr/bin/env node

const assert = require('assert')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync, spawnSync } = require('child_process')
const { pathToFileURL } = require('url')

const root = path.resolve(__dirname, '..', '..')
const ciPath = path.join(root, '.github', 'workflows', 'ci.yml')
const legacyReleasePath = path.join(root, '.github', 'workflows', 'release.yml')
const repairPath = path.join(root, '.github', 'workflows', 'release-repair.yml')
const weeklyPath = path.join(root, '.github', 'workflows', 'weekly-ci-evidence.yml')
const packagePath = path.join(root, 'package.json')
const packageSmokePath = path.join(root, 'scripts', 'ci', 'package-smoke.sh')

function requireMatch(text, pattern, message) {
  assert.match(text, pattern, message)
}

function assertRustPolicyGithubBoundary() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-policy-output-'))
  const githubEnvironment = path.join(temp, 'github-env')
  const githubOutput = path.join(temp, 'github-output')
  try {
    execFileSync(process.execPath, [
      path.join(root, 'scripts', 'ci', 'rust-toolchain-policy.js'),
      '--github-output',
      '--activate',
      'release'
    ], {
      cwd: root,
      env: {
        GITHUB_ENV: githubEnvironment,
        GITHUB_OUTPUT: githubOutput,
        LANG: 'C'
      },
      stdio: ['ignore', 'pipe', 'pipe']
    })
    assert.match(fs.readFileSync(githubEnvironment, 'utf8'), /^RUSTUP_TOOLCHAIN=\d+\.\d+\.\d+\n$/)
    assert.match(fs.readFileSync(githubOutput, 'utf8'), /^minimum=.*\nrelease=.*\ncurrent=.*\n$/)
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

function assertSingleTagGitGuard() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-git-guard-'))
  const fakeGit = path.join(temp, 'git')
  const log = path.join(temp, 'git.log')
  const sourceCommit = 'a'.repeat(40)
  try {
    fs.writeFileSync(
      fakeGit,
      `#!/bin/sh\nprintf '%s\\n' "$*" >> ${JSON.stringify(log)}\ncase "$*" in *rev-parse*) printf '%s\\n' ${sourceCommit} ;; esac\n`,
      { mode: 0o755 }
    )
    execFileSync(path.join(root, 'scripts', 'release', 'git-command-guard.sh'), [
      'push', '--tags', 'https://example.invalid/repository.git'
    ], {
      env: {
        RELEASE_APPROVED_TAG: 'v1.2.3',
        RELEASE_GIT_BIN: fakeGit,
        RELEASE_SOURCE_COMMIT: sourceCommit
      }
    })
    const calls = fs.readFileSync(log, 'utf8')
    assert(!/push .*--tags/.test(calls), 'the delegated Git push must never retain --tags')
    assert.match(
      calls,
      /push --no-verify https:\/\/example\.invalid\/repository\.git refs\/tags\/v1\.2\.3:refs\/tags\/v1\.2\.3/,
      'the Git guard must publish only the approved release tag ref'
    )
    const rejected = spawnSync(
      path.join(root, 'scripts', 'release', 'git-command-guard.sh'),
      ['push', '--tags', 'https://example.invalid/repository.git'],
      { env: { RELEASE_GIT_BIN: fakeGit, RELEASE_SOURCE_COMMIT: sourceCommit } }
    )
    assert.notStrictEqual(rejected.status, 0, 'a broad tag push without one approved tag must fail')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

async function assertSemanticReleaseGithubCredential() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-semantic-auth-'))
  const fakeGit = path.join(temp, 'git')
  const credentialUser = ['x', 'access', 'token'].join('-')
  const fixtureCredential = ['fixture', 'token'].join('-')
  try {
    fs.writeFileSync(
      fakeGit,
      `#!/bin/sh\ncase "$*" in *${credentialUser}:${fixtureCredential}@github.com*) exit 0 ;; *) exit 1 ;; esac\n`,
      { mode: 0o755 }
    )
    const source = path.join(root, 'node_modules', 'semantic-release', 'lib', 'get-git-auth-url.js')
    const { default: getGitAuthUrl } = await import(pathToFileURL(source).href)
    const authUrl = await getGitAuthUrl({
      branch: { name: 'main' },
      cwd: root,
      env: {
        GITHUB_ACTION: 'release',
        GH_TOKEN: fixtureCredential,
        GITHUB_TOKEN: fixtureCredential,
        PATH: temp
      },
      options: { repositoryUrl: 'https://github.com/example/reflaxe.rust.git' }
    })
    assert.strictEqual(
      authUrl,
      `https://${credentialUser}:${fixtureCredential}@github.com/example/reflaxe.rust.git`,
      'the locked semantic-release path must use GitHub Actions installation-token credentials'
    )
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

function assertExactRepairTagResolution() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-repair-ref-'))
  try {
    execFileSync('/usr/bin/git', ['init', '-b', 'main'], { cwd: temp, stdio: 'ignore' })
    execFileSync('/usr/bin/git', ['config', 'user.name', 'Release Workflow Test'], { cwd: temp })
    execFileSync('/usr/bin/git', ['config', 'user.email', 'release-workflow@example.invalid'], { cwd: temp })
    fs.writeFileSync(path.join(temp, 'fixture.txt'), 'reviewed\n')
    execFileSync('/usr/bin/git', ['add', 'fixture.txt'], { cwd: temp })
    execFileSync('/usr/bin/git', ['commit', '-m', 'test: seed repair ref'], { cwd: temp, stdio: 'ignore' })
    execFileSync('/usr/bin/git', ['branch', 'v1.2.3'], { cwd: temp })
    const branchOnly = spawnSync('/usr/bin/git', ['rev-parse', 'refs/tags/v1.2.3^{commit}'], {
      cwd: temp,
      stdio: 'ignore'
    })
    assert.notStrictEqual(branchOnly.status, 0, 'a version-shaped branch must not resolve as a repair tag')
    execFileSync('/usr/bin/git', ['tag', 'v1.2.3'], { cwd: temp })
    assert.strictEqual(
      execFileSync('/usr/bin/git', ['rev-parse', 'refs/tags/v1.2.3^{commit}'], { cwd: temp, encoding: 'utf8' }).trim(),
      execFileSync('/usr/bin/git', ['rev-parse', 'HEAD^{commit}'], { cwd: temp, encoding: 'utf8' }).trim()
    )
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

async function main() {
  const ci = fs.readFileSync(ciPath, 'utf8')
  const packageSmoke = fs.readFileSync(packageSmokePath, 'utf8')
  assert(
    !packageSmoke.includes('HAXE_LIBRARY_PATH='),
    'the raw release Haxe binary must not receive a Lix-only library-path hint'
  )
  requireMatch(
    packageSmoke,
    /"\$RELEASE_HAXE_BIN"[\s\\]*-cp "\$source_app_dir"[\s\\]*-cp "\$root_dir\/src"[\s\\]*-cp "\$root_dir\/std"[\s\\]*-cp "\$root_dir\/std\/rust\/_std"[\s\\]*-cp "\$root_dir\/vendor\/reflaxe\/src"/,
    'the isolated source-layout smoke must pass every reviewed target and framework classpath to the raw Haxe executable'
  )
  requireMatch(
    packageSmoke,
    /-D reflaxe=4\.0\.0-beta[\s\\]*-D reflaxe\.rust=0\.0\.0-development[\s\\]*--macro 'nullSafety\("reflaxe\.rust"\)'[\s\\]*--macro 'reflaxe\.rust\.CompilerBootstrap\.Start\(\)'[\s\\]*--macro 'reflaxe\.rust\.CompilerInit\.Start\(\)'/,
    'the isolated source-layout smoke must activate the exact reviewed Reflaxe and Rust compiler macros'
  )
  requireMatch(
    packageSmoke,
    /JSON\.stringify\(\{ version: source\.version, resolveLibs: 'haxelib' \}[\s\S]*"\$RELEASE_HAXE_BIN" -cp \. -lib reflaxe\.rust/,
    'the isolated installed-package smoke must force library resolution through its temporary Haxelib repository'
  )
  assert(!ci.includes('workflow_run'), 'normal publication must not cross a privileged workflow_run boundary')
  assert(!fs.existsSync(legacyReleasePath), 'the separate normal Release workflow must be removed')
  requireMatch(
    ci,
    /node scripts\/ci\/npm-audit-policy\.js\n/,
    'the fail-closed dependency audit policy must be part of the release gate'
  )

  const releaseStart = ci.indexOf('\n  release:\n')
  assert(releaseStart !== -1, 'CI must contain a release job')
  const release = ci.slice(releaseStart)
  requireMatch(release, /if: github\.event_name == 'push' && github\.ref == 'refs\/heads\/main'/, 'release must be push/main only')
  for (const required of ['security', 'rust-tooling', 'rust-current-stable', 'windows-smoke', 'rustsec-audit', 'test', 'tier2-stdlib-sweep']) {
    requireMatch(release, new RegExp(`- ${required.replace('-', '\\-')}`), `release must wait for ${required}`)
  }
  requireMatch(release, /contents: write/, 'only the release job needs contents write authority')
  requireMatch(release, /group: release-\$\{\{ github\.repository \}\}/, 'all normal publication must serialize in one repository group')
  requireMatch(release, /ref: \$\{\{ github\.sha \}\}/, 'release checkout must use the exact CI-tested SHA')
  requireMatch(release, /actions\/checkout@[0-9a-f]{40}/, 'privileged checkout must pin a full action commit')
  requireMatch(release, /actions\/setup-node@[0-9a-f]{40}/, 'privileged Node setup must pin a full action commit')
  requireMatch(release, /node-version: "22\.14\.0"/, 'release Node runtime must be exact')
  requireMatch(
    release,
    /shell: \/usr\/bin\/bash --noprofile --norc -euo pipefail \{0\}/,
    'release steps must start under a profile-free absolute Bash before any script text runs'
  )
  requireMatch(release, /BASH_ENV: ""[\s\S]*ENV: ""[\s\S]*NODE_OPTIONS: ""/, 'release job startup must clear shell and Node preload variables')
  requireMatch(release, /node_bin="\$\(\/usr\/bin\/readlink -f "\$\(command -v node\)"\)"[\s\S]*"\$node_bin" --version/, 'release must capture and validate the setup-node executable by absolute path')
  requireMatch(release, /RUNNER_TOOL_CACHE\/node\/22\.14\.0/, 'release must bind Node to setup-node\'s pinned tool-cache directory')
  requireMatch(
    release,
    /\/bin\/cp \.haxerc "\$RUNNER_TEMP\/haxe-rust-lix-home\/haxe\/\.haxerc"[\s\S]*release_home="\$RUNNER_TEMP\/haxe-rust-lix-home"/,
    'release must use one fresh Lix home with an exact global Haxe version inside temporary build directories'
  )
  requireMatch(
    release,
    /\/usr\/bin\/env -i HOME="\$RUNNER_TEMP\/haxe-rust-lix-home" LANG=C[\s\\]*"\$RELEASE_NODE_BIN" "\$haxe_bin" -version/,
    'release must verify the Haxe shim with the exact Node executable and the same isolated Lix home'
  )
  requireMatch(
    release,
    /\/usr\/bin\/git --no-replace-objects[^\n]*[\s\S]*fsck --strict --full --no-reflogs "\$SOURCE_COMMIT"[\s\S]*cat-file blob/,
    'release must validate reachable Git object identities before extracting executable bootstrap bytes'
  )
  requireMatch(
    release,
    /git --no-replace-objects cat-file blob[\s\S]*SOURCE_COMMIT:scripts\/release\/exact-git-source\.js/,
    'the workflow must load its release bootstrap from the tested commit rather than the live checkout'
  )
  requireMatch(
    release,
    /"\$node_bin" "\$bootstrap" bootstrap[\s\S]*"\$GITHUB_WORKSPACE" "\$SOURCE_COMMIT" "\$source_root"[\s\S]*"\$GITHUB_SERVER_URL\/\$GITHUB_REPOSITORY\.git"/,
    'the workflow must create an exact-object release repository before loading release code'
  )
  assert(!release.includes('remote set-url'), 'the bootstrap receipt must be written after the final reviewed origin is configured')
  requireMatch(
    release,
    /RELEASE_NODE_BIN=\$node_bin[\s\S]*RELEASE_GIT_BIN=\/usr\/bin\/git[\s\S]*RELEASE_SOURCE_COMMIT=\$SOURCE_COMMIT/,
    'the workflow must retain absolute reviewed tool paths and exact source identity'
  )
  const releaseAssert = release.indexOf('"$RELEASE_NODE_BIN" "$final_bootstrap" assert')
  const semanticRelease = release.indexOf('semantic-release/bin/semantic-release.js')
  assert(releaseAssert !== -1, 'release must re-extract and run a fresh literal bootstrap after tool installation')
  assert(releaseAssert < semanticRelease, 'literal commit-byte proof must precede semantic-release loading')
  const finalBootstrap = release.lastIndexOf('cat-file blob', releaseAssert)
  const finalFsck = release.lastIndexOf('fsck --strict --full --no-reflogs', releaseAssert)
  assert(finalBootstrap !== -1 && finalFsck !== -1 && finalFsck < finalBootstrap, 'final release assertion must fsck then freshly extract its checker')
  requireMatch(
    release.slice(releaseAssert, semanticRelease),
    /"\$GITHUB_SERVER_URL\/\$GITHUB_REPOSITORY\.git"/,
    'final release assertion must compare Git configuration with the workflow-owned repository URL'
  )
  assert(!release.includes('RELEASE_BOOTSTRAP='), 'a writable bootstrap extracted before dependency setup must never be reused as release authority')
  for (const command of ['RELEASE_NPM_BIN" ci', '"$lix" download', 'rust-toolchain-policy.js', 'semantic-release/bin/semantic-release.js']) {
    const commandIndex = release.indexOf(command)
    assert(commandIndex > release.indexOf('Materialize exact reviewed release repository'), `${command} must run only after exact-source bootstrap`)
    const preceding = release.slice(Math.max(0, commandIndex - 500), commandIndex)
    requireMatch(preceding, /RELEASE_SOURCE_ROOT/, `${command} must run from the exact reviewed repository`)
  }
  requireMatch(release, /env -i[\s\S]*RELEASE_CARGO_BIN="\$cargo_bin"[\s\S]*RELEASE_NODE_BIN="\$RELEASE_NODE_BIN"/, 'publication must use an explicit allowlisted execution environment')
  requireMatch(
    release,
    /env -i LANG=C GITHUB_ENV="\$GITHUB_ENV" GITHUB_OUTPUT="\$GITHUB_OUTPUT"[\s\\]*"\$RELEASE_NODE_BIN"[\s\\]*scripts\/ci\/rust-toolchain-policy\.js --github-output --activate release/,
    'release Rust policy resolution must preserve GitHub output files through env -i'
  )
  requireMatch(
    release.slice(releaseAssert, semanticRelease),
    /GITHUB_ACTION="\$GITHUB_ACTION"/,
    'semantic-release must receive the GitHub Actions credential-mode marker'
  )
  requireMatch(release, /RELEASE_EXPECTED_ORIGIN_URL="\$GITHUB_SERVER_URL\/\$GITHUB_REPOSITORY\.git"/, 'release callers must retain the workflow-owned repository URL')
  requireMatch(
    release.slice(releaseAssert, semanticRelease),
    /GIT_ATTR_NOSYSTEM=1[\s\S]*GIT_CONFIG_GLOBAL=\/dev\/null[\s\S]*GIT_CONFIG_NOSYSTEM=1[\s\S]*GIT_NO_REPLACE_OBJECTS=1/,
    'semantic-release itself must inherit replacement-free, system/global-config-free Git behavior'
  )
  requireMatch(
    release,
    /\/bin\/ln -s "\$git_guard" "\$tool_dir\/git"[\s\S]*RELEASE_GIT_GUARD_BIN=/,
    'semantic-release Git calls must pass through the reviewed single-tag publication guard'
  )
  requireMatch(
    release.slice(releaseAssert, semanticRelease),
    /PATH="\$RELEASE_TOOL_DIR:\/usr\/bin:\/bin"/,
    'semantic-release PATH must resolve git through the reviewed guard before the system executable'
  )
  const hostControl = release.indexOf('scripts/release/verify-host-tag-controls.js')
  assert(hostControl > releaseAssert && hostControl < semanticRelease, 'token-readable host tag controls must be checked immediately before publication authority')
  assert(
    !release.includes('scripts/release/verify-host-controls.js'),
    'the short-lived release token must not call the maintainer-only repository-administration audit'
  )
  assert(!release.includes('actions/cache'), 'the privileged release job must not restore an executable cache')
  assert(!release.includes('workflow_dispatch'), 'normal publication must not have a manual bypass')

  assert(fs.existsSync(repairPath), 'an existing-tag repair-only workflow must exist')
  const repair = fs.readFileSync(repairPath, 'utf8')
  requireMatch(repair, /workflow_dispatch:/, 'repair must be explicitly manual')
  requireMatch(repair, /tag:\n\s+description:/, 'repair must require a tag input')
  assert(!repair.includes("if: startsWith(inputs.tag, 'v')"), 'invalid repair input must fail explicitly instead of skipping the write-capable job')
  requireMatch(
    repair,
    /\[\[ ! "\$REPAIR_TAG" =~ \^v\(0\|\[1-9\]\[0-9\]\*\)\\\.\(0\|\[1-9\]\[0-9\]\*\)\\\.\(0\|\[1-9\]\[0-9\]\*\)\$ \]\]/,
    'repair must validate exact stable-version syntax before checkout'
  )
  requireMatch(repair, /ref: refs\/tags\/\$\{\{ inputs\.tag \}\}/, 'repair must check out the explicit immutable tag namespace')
  requireMatch(repair, /shell: \/usr\/bin\/bash --noprofile --norc -euo pipefail \{0\}/, 'repair steps must use profile-free absolute Bash')
  requireMatch(repair, /BASH_ENV: ""[\s\S]*ENV: ""[\s\S]*NODE_OPTIONS: ""/, 'repair startup must clear shell and Node preload variables')
  requireMatch(
    repair,
    /\/bin\/cp \.haxerc "\$RUNNER_TEMP\/haxe-rust-lix-home\/haxe\/\.haxerc"[\s\S]*release_home="\$RUNNER_TEMP\/haxe-rust-lix-home"/,
    'repair must use one fresh Lix home with an exact global Haxe version inside temporary build directories'
  )
  requireMatch(
    repair,
    /\/usr\/bin\/env -i HOME="\$RUNNER_TEMP\/haxe-rust-lix-home" LANG=C[\s\\]*"\$RELEASE_NODE_BIN" "\$haxe_bin" -version/,
    'repair must verify the Haxe shim with the exact Node executable and the same isolated Lix home'
  )
  requireMatch(repair, /REPAIR_TAG: \$\{\{ inputs\.tag \}\}/, 'manual input must cross into shell through an environment value')
  requireMatch(
    repair,
    /git --no-replace-objects cat-file blob[\s\S]*source_commit:scripts\/release\/exact-git-source\.js/,
    'repair must load its bootstrap from the supplied tag object'
  )
  requireMatch(
    repair,
    /RELEASE_NODE_BIN=\$node_bin[\s\S]*RELEASE_GIT_BIN=\/usr\/bin\/git[\s\S]*RELEASE_SOURCE_COMMIT=\$source_commit/,
    'repair must retain absolute reviewed tool paths and supplied tag identity'
  )
  requireMatch(repair, /rev-parse --verify "refs\/tags\/\$REPAIR_TAG\^\{commit\}"/, 'repair source resolution must use the explicit tag namespace')
  requireMatch(repair, /test "\$head_commit" = "\$source_commit"/, 'repair must prove checkout HEAD equals the supplied tag commit')
  const repairAssert = repair.indexOf('"$RELEASE_NODE_BIN" "$final_bootstrap" assert')
  const repairCommand = repair.indexOf('"$RELEASE_NODE_BIN" scripts/release/repair-release.js "$REPAIR_TAG"')
  assert(repairAssert !== -1, 'repair must recheck literal commit bytes after tool installation')
  assert(repairAssert < repairCommand, 'literal commit-byte proof must precede repair code loading')
  requireMatch(
    repair.slice(repairAssert, repairCommand),
    /"\$GITHUB_SERVER_URL\/\$GITHUB_REPOSITORY\.git"/,
    'final repair assertion must compare Git configuration with the workflow-owned repository URL'
  )
  assert(!repair.includes('RELEASE_BOOTSTRAP='), 'repair must not reuse a writable pre-install bootstrap')
  requireMatch(repair, /cd "\$RELEASE_SOURCE_ROOT"[\s\S]*repair-release\.js/, 'repair must execute from the exact tag repository')
  requireMatch(repair, /env -i[\s\S]*RELEASE_CARGO_BIN="\$cargo_bin"[\s\S]*RELEASE_NODE_BIN="\$RELEASE_NODE_BIN"/, 'repair must use an explicit allowlisted execution environment')
  requireMatch(
    repair,
    /env -i LANG=C GITHUB_ENV="\$GITHUB_ENV" GITHUB_OUTPUT="\$GITHUB_OUTPUT"[\s\\]*"\$RELEASE_NODE_BIN"[\s\\]*scripts\/ci\/rust-toolchain-policy\.js --github-output --activate release/,
    'repair Rust policy resolution must preserve GitHub output files through env -i'
  )
  requireMatch(
    repair,
    /GIT_ATTR_NOSYSTEM=1[\s\S]*GIT_CONFIG_GLOBAL=\/dev\/null[\s\S]*GIT_CONFIG_NOSYSTEM=1[\s\S]*GIT_NO_REPLACE_OBJECTS=1/,
    'repair must preserve replacement-free, system/global-config-free Git behavior through its final process'
  )
  requireMatch(
    repair,
    /scripts\/release\/verify-host-tag-controls\.js[\s\S]*scripts\/release\/repair-release\.js/,
    'repair must verify token-readable immutable-tag controls before receiving publication authority'
  )
  assert(
    !repair.includes('scripts/release/verify-host-controls.js'),
    'the short-lived repair token must not call the maintainer-only repository-administration audit'
  )
  requireMatch(repair, /RELEASE_EXPECTED_ORIGIN_URL="\$GITHUB_SERVER_URL\/\$GITHUB_REPOSITORY\.git"/, 'repair callers must retain the workflow-owned repository URL')
  requireMatch(repair, /"\$RELEASE_NODE_BIN" scripts\/release\/repair-release\.js "\$REPAIR_TAG"/, 'repair must use the non-version-deriving repair command')
  assert(!repair.includes('semantic-release'), 'repair must never derive or create a new version')
  assert(!repair.includes('git tag'), 'repair must never create, move, or delete a tag')

  assert(fs.existsSync(weeklyPath), 'the sustained-stability evidence workflow must exist')
  const weekly = fs.readFileSync(weeklyPath, 'utf8')
  const packageJson = JSON.parse(fs.readFileSync(packagePath, 'utf8'))
  const ciNode = ci.match(/^  NODE_VERSION: "([^"]+)"$/m)?.[1]
  const weeklyNode = weekly.match(/^  NODE_VERSION: "([^"]+)"$/m)?.[1]
  assert(ciNode, 'CI must declare its exact Node runtime')
  assert.strictEqual(weeklyNode, ciNode, 'weekly evidence and normal CI must use the same Node runtime')
  assert(
    String(packageJson.engines?.node || '').startsWith(`>=${weeklyNode} `),
    'weekly evidence Node must match the package engine minimum'
  )
  requireMatch(weekly, /cron: "0 10 \* \* 1"/, 'weekly evidence must retain the Monday 10:00 UTC cadence')
  requireMatch(weekly, /workflow_dispatch: \{\}/, 'weekly evidence must support deliberate reruns')
  requireMatch(weekly, /group: weekly-ci-evidence-\$\{\{ github\.ref \}\}/, 'weekly evidence runs must serialize per ref')
  requireMatch(weekly, /cancel-in-progress: false/, 'a later trigger must not cancel an evidence run already in progress')
  for (const requiredJob of ['local-equivalent', 'windows-smoke', 'codex-hxrust-qa', 'follow-up-guidance']) {
    requireMatch(weekly, new RegExp(`\\n  ${requiredJob.replaceAll('-', '\\-')}:\\n`), `weekly evidence must retain ${requiredJob}`)
  }
  requireMatch(weekly, /Commit: \\?`\$\{\{ github\.sha \}\}\\?`/, 'Linux weekly evidence must record the exact compiler SHA')
  requireMatch(weekly, /haxe\.rust commit: \\?`\$\{haxe_rust_sha\}\\?`/, 'killer-app evidence must record the compiler SHA')
  requireMatch(weekly, /codex-hxrust commit: \\?`\$\{codex_hxrust_sha\}\\?`/, 'killer-app evidence must record the app SHA')
  for (const requiredNeed of ['local-equivalent', 'windows-smoke', 'codex-hxrust-qa']) {
    requireMatch(weekly, new RegExp(`- ${requiredNeed.replaceAll('-', '\\-')}`), `weekly rollup must wait for ${requiredNeed}`)
  }

  assertRustPolicyGithubBoundary()
  assertSingleTagGitGuard()
  await assertSemanticReleaseGithubCredential()
  assertExactRepairTagResolution()

  console.log('[release-workflow-test] OK')
}

main().catch((error) => {
  console.error(error.stack || error.message)
  process.exit(1)
})
