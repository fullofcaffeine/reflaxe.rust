#!/usr/bin/env node

const assert = require('assert')
const { execFileSync } = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { assertPackageInputsTracked } = require('../../scripts/release/package-input-cleanliness.js')
const repoRoot = path.resolve(__dirname, '..', '..')

function git(cwd, args) {
  return execFileSync('git', args, { cwd, encoding: 'utf8' })
}

function main() {
	const completeIndex = execFileSync('git', ['ls-files', '--stage', '-z'], {
		cwd: repoRoot,
		maxBuffer: 8 * 1024 * 1024
	})
	assert(completeIndex.length > 1024 * 1024, 'the real-repository regression must exceed Node\'s default buffer')
	assert.doesNotThrow(
		() => assertPackageInputsTracked(repoRoot),
		'the release-input guard must process the complete reviewed repository without ENOBUFS'
	)
	const largeIndex = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-large-package-index-'))
	try {
		git(largeIndex, ['init', '-q'])
		const blob = execFileSync('git', ['hash-object', '-w', '--stdin'], {
			cwd: largeIndex,
			input: 'class Generated {}\n',
			encoding: 'utf8'
		}).trim()
		const records = []
		for (let index = 0; index < 18000; index += 1) {
			records.push(`100644 ${blob}\tsrc/generated/Entry${String(index).padStart(5, '0')}.hx\0`)
		}
		execFileSync('git', ['update-index', '-z', '--index-info'], {
			cwd: largeIndex,
			input: records.join(''),
			maxBuffer: 8 * 1024 * 1024
		})
		const generatedIndex = execFileSync('git', ['ls-files', '--stage', '-z'], {
			cwd: largeIndex,
			maxBuffer: 8 * 1024 * 1024
		})
		assert(generatedIndex.length > 1024 * 1024, 'the generated Git index must exceed 1 MiB')
		assert.doesNotThrow(
			() => assertPackageInputsTracked(largeIndex),
			'a generated repository-sized index must return a package integrity result'
		)
	} finally {
		fs.rmSync(largeIndex, { recursive: true, force: true })
	}

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-package-input-cleanliness-'))
  try {
    git(temp, ['init', '-q'])
    fs.mkdirSync(path.join(temp, 'src'), { recursive: true })
    fs.writeFileSync(path.join(temp, 'src', 'Tracked.hx'), 'class Tracked {}\n')
    fs.writeFileSync(
      path.join(temp, '.gitignore'),
      'vendor/haxe/\n*.n\ndocs/stdlib-provenance-ledger.json\n'
    )
    git(temp, ['add', '.'])
    git(temp, [
      '-c',
      'user.name=Package Test',
      '-c',
      'user.email=package@example.invalid',
      'commit',
      '-q',
      '-m',
      'fixture'
    ])
    assert.doesNotThrow(() => assertPackageInputsTracked(temp))

    fs.writeFileSync(path.join(temp, 'local-notes.txt'), 'outside package roots\n')
    assert.doesNotThrow(() => assertPackageInputsTracked(temp))

    fs.mkdirSync(path.join(temp, 'runtime'), { recursive: true })
    fs.writeFileSync(path.join(temp, 'runtime', 'payload.rs'), 'untracked\n')
    assert.throws(() => assertPackageInputsTracked(temp), /runtime\/payload\.rs/)
    fs.rmSync(path.join(temp, 'runtime'), { recursive: true })

    fs.mkdirSync(path.join(temp, 'vendor', 'haxe'), { recursive: true })
    fs.writeFileSync(path.join(temp, 'vendor', 'haxe', 'payload.hx'), 'ignored but packaged\n')
    assert.throws(() => assertPackageInputsTracked(temp), /vendor\/haxe\/payload\.hx/)
    fs.rmSync(path.join(temp, 'vendor'), { recursive: true })

    fs.writeFileSync(path.join(temp, 'run.n'), 'ignored executable input\n')
    assert.throws(() => assertPackageInputsTracked(temp), /run\.n/)
    fs.rmSync(path.join(temp, 'run.n'))

    fs.writeFileSync(path.join(temp, 'Run.hx'), 'untracked source input\n')
    assert.throws(() => assertPackageInputsTracked(temp), /Run\.hx/)
    fs.rmSync(path.join(temp, 'Run.hx'))

    fs.mkdirSync(path.join(temp, 'docs'), { recursive: true })
    fs.writeFileSync(
      path.join(temp, 'docs', 'stdlib-provenance-ledger.json'),
      '{"unreviewed":true}\n'
    )
    assert.throws(
      () => assertPackageInputsTracked(temp),
      /docs\/stdlib-provenance-ledger\.json/
    )
    fs.rmSync(path.join(temp, 'docs', 'stdlib-provenance-ledger.json'))

    const external = path.join(temp, '..', `external-${path.basename(temp)}.json`)
    fs.writeFileSync(external, '{"external":true}\n')
    fs.symlinkSync(external, path.join(temp, 'docs', 'stdlib-provenance-ledger.json'))
    git(temp, ['add', '-f', 'docs/stdlib-provenance-ledger.json'])
    git(temp, [
      '-c',
      'user.name=Package Test',
      '-c',
      'user.email=package@example.invalid',
      'commit',
      '-q',
      '-m',
      'tracked symlink'
    ])
    assert.strictEqual(git(temp, ['status', '--porcelain', '--untracked-files=no']), '')
    assert.throws(
      () => assertPackageInputsTracked(temp),
      /release package input must be a regular Git blob: docs\/stdlib-provenance-ledger\.json/
    )
    fs.rmSync(external)

		for (const packageRoot of ['src', 'std', 'runtime', 'vendor']) {
			const gitlinkFixture = path.join(temp, `gitlink-${packageRoot}`)
			fs.mkdirSync(gitlinkFixture)
			git(gitlinkFixture, ['init', '-q'])
			fs.writeFileSync(path.join(gitlinkFixture, 'README.md'), '# fixture\n')
			git(gitlinkFixture, ['add', '.'])
			git(gitlinkFixture, [
				'-c',
				'user.name=Package Test',
				'-c',
				'user.email=package@example.invalid',
				'commit',
				'-q',
				'-m',
				'fixture'
			])
			const commit = git(gitlinkFixture, ['rev-parse', 'HEAD']).trim()
			git(gitlinkFixture, ['update-index', '--add', '--cacheinfo', `160000,${commit},${packageRoot}`])
			assert.throws(
				() => assertPackageInputsTracked(gitlinkFixture),
				new RegExp(`release package input must be a regular Git blob: ${packageRoot}`),
				`an exact ${packageRoot} gitlink must not supply package bytes outside the reviewed commit`
			)
			git(gitlinkFixture, ['update-index', '--force-remove', packageRoot])
			const externalRoot = path.join(temp, `external-${packageRoot}`)
			fs.mkdirSync(externalRoot)
			fs.writeFileSync(path.join(externalRoot, 'payload.txt'), 'external package bytes\n')
			fs.symlinkSync(externalRoot, path.join(gitlinkFixture, packageRoot), 'dir')
			git(gitlinkFixture, ['add', packageRoot])
			assert.throws(
				() => assertPackageInputsTracked(gitlinkFixture),
				new RegExp(`release package input must be a regular Git blob: ${packageRoot}`),
				`an exact ${packageRoot} symlink must not supply package bytes outside the reviewed commit`
			)
		}

		const licenseSymlinkFixture = path.join(temp, 'license-symlink')
		const externalLicense = path.join(temp, 'external-haxe-license.txt')
		fs.mkdirSync(path.join(licenseSymlinkFixture, 'docs', 'licenses'), { recursive: true })
		fs.writeFileSync(externalLicense, 'external license bytes\n')
		fs.symlinkSync(
			externalLicense,
			path.join(licenseSymlinkFixture, 'docs', 'licenses', 'haxe-stdlib-4.3.7-MIT.txt')
		)
		git(licenseSymlinkFixture, ['init', '-q'])
		git(licenseSymlinkFixture, ['add', '.'])
		git(licenseSymlinkFixture, [
			'-c',
			'user.name=Package Test',
			'-c',
			'user.email=package@example.invalid',
			'commit',
			'-q',
			'-m',
			'tracked external license symlink'
		])
		assert.throws(
			() => assertPackageInputsTracked(licenseSymlinkFixture),
			/release package input must be a regular Git blob: docs\/licenses\/haxe-stdlib-4\.3\.7-MIT\.txt/
		)

    console.log('[package-input-cleanliness-test] OK')
  } finally {
    fs.rmSync(temp, { recursive: true, force: true })
  }
}

main()
