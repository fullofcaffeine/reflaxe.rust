#!/usr/bin/env node

const assert = require('assert')
const cp = require('child_process')
const fs = require('fs')
const os = require('os')
const path = require('path')

const repoRoot = path.resolve(__dirname, '..', '..')
const checker = path.join(repoRoot, 'scripts', 'ci', 'public-compatibility-manifest-check.js')
const sourceManifest = path.join(repoRoot, 'docs', 'public-compatibility-manifest.json')
const fixtureRoot = path.join(repoRoot, 'test', 'fixtures', 'public_compatibility_surface')
const checkerModule = require(checker)

function run(args) {
  return cp.spawnSync(process.execPath, [checker, ...args], {
    cwd: repoRoot,
    encoding: 'utf8'
  })
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`)
}

function expectFailure(result, pattern) {
  assert.notStrictEqual(result.status, 0, 'guard unexpectedly succeeded')
  assert.match(`${result.stdout}\n${result.stderr}`, pattern)
}

function operation(type, id) {
  const found = type.operations.find((entry) => entry.id === id)
  assert(found, `${type.name} must contain operation ${id}`)
  return found
}

function main() {
  assert(fs.existsSync(checker), 'public compatibility guard must exist')
  assert(fs.existsSync(sourceManifest), 'public compatibility manifest must exist')

  const baseline = run([])
  assert.strictEqual(baseline.status, 0, baseline.stderr || baseline.stdout)

  const canonical = JSON.parse(fs.readFileSync(sourceManifest, 'utf8'))
  assert.strictEqual(canonical.schemaVersion, 2, 'the package-complete graph must use schema v2')
  assert.deepStrictEqual(canonical.surfaceScope.sourceRoots, ['src/reflaxe/rust', 'std'])
  assert(canonical.evidence.some((entry) => entry.id === 'test:public-compatibility' && entry.kind === 'npm-script'),
    'the graph must own an executable structural-evidence ID')

  const rootSys = canonical.haxeTypes.find((entry) => entry.name === 'Sys')
  assert(rootSys, 'package discovery must include no-package std overrides')
  const stdin = canonical.haxeTypes.find((entry) => entry.name === 'sys.io.Stdin')
  assert(stdin, 'package discovery must include std declarations outside std/rust')
  const nativeSys = canonical.haxeTypes.find((entry) => entry.name === 'hxrt.sys.NativeSys')
  assert(nativeSys, 'package discovery must include importable hxrt helpers')
  assert.strictEqual(nativeSys.contract, 'internal-helper')
  const compilerType = canonical.haxeTypes.find((entry) => entry.name === 'reflaxe.rust.RustCompiler')
  assert(compilerType, 'package discovery must include shipped compiler declarations')
  assert.strictEqual(compilerType.contract, 'internal-helper')
  assert.deepStrictEqual(checkerModule.internalHelperRoots(), [
    'haxe.BoundaryTypes',
    'hxrt',
    'reflaxe.rust',
    'rust._internal'
  ], 'the graph guard must consume the compiler-owned internal namespace policy')
  assert.deepStrictEqual(checkerModule.internalHelperExceptions(), [
    'reflaxe.rust.macros.RustInjection'
  ], 'mixed namespaces must expose only explicitly classified public exceptions')
  const rustInjection = canonical.haxeTypes.find((entry) => entry.name === 'reflaxe.rust.macros.RustInjection')
  assert.strictEqual(rustInjection.contract, 'raw-experimental', 'the documented injection shim must remain explicitly public and experimental')

  const resultType = canonical.haxeTypes.find((entry) => entry.name === 'rust.Result')
  assert.match(resultType.signature, /E = String/, 'type signatures must preserve generic defaults')
  operation(resultType, 'enum-constructor:Ok')
  operation(resultType, 'enum-constructor:Err')

  const mutexes = canonical.haxeTypes.find((entry) => entry.name === 'rust.concurrent.Mutexes')
  const rwLocks = canonical.haxeTypes.find((entry) => entry.name === 'rust.concurrent.RwLocks')
  const concurrencyContract = canonical.contracts.find((entry) => entry.id === 'rust-concurrency')
  assert(concurrencyContract.evidenceIds.includes('test:native-lock-reentrancy'),
    'the qualified Rust lock contract must own executable reentrancy evidence')
  assert.match(concurrencyContract.qualification, /HXRT-LOCK-REENTRANCY/,
    'the qualified Rust lock contract must name its same-handle failure boundary')
  for (const type of [mutexes, rwLocks]) {
    assert(type.evidenceIds.includes('test:native-lock-reentrancy'),
      `${type.name} must own executable reentrancy evidence`)
    for (const entry of type.operations) {
      assert(entry.evidenceIds.includes('test:native-lock-reentrancy'),
        `${type.name}.${entry.name} must own executable reentrancy evidence`)
    }
  }
  const portableSysContract = canonical.contracts.find((entry) => entry.id === 'portable-sys-core')
  assert(portableSysContract.evidenceIds.includes('test:thread-event-loop-lifecycle'),
    'the portable thread/EventLoop contract must own executable lifecycle evidence')
  assert(portableSysContract.protectedContract.some((value) => value.includes('HXRT-THREAD-NOT-ALIVE')),
    'the portable thread contract must protect its dead-thread failure identifier')
  assert(portableSysContract.protectedContract.some((value) => value.includes('HXRT-EVENTLOOP-PROMISE-UNDERFLOW')),
    'the portable EventLoop contract must protect promise balance and its failure identifier')
  const eventLoop = canonical.haxeTypes.find((entry) => entry.name === 'sys.thread.EventLoop')
  const thread = canonical.haxeTypes.find((entry) => entry.name === 'sys.thread.Thread')
  for (const type of [eventLoop, thread]) {
    assert(type.evidenceIds.includes('test:thread-event-loop-lifecycle'),
      `${type.name} must own executable lifecycle evidence`)
  }
  for (const operationId of [
    'function:repeat',
    'function:cancel',
    'function:promise',
    'function:run',
    'function:runPromised',
    'function:progress',
    'function:loop'
  ]) {
    assert(operation(eventLoop, operationId).evidenceIds.includes('test:thread-event-loop-lifecycle'),
      `sys.thread.EventLoop.${operationId} must own executable lifecycle evidence`)
  }
  for (const operationId of [
    'function:sendMessage',
    'function:current',
    'function:create',
    'function:createWithEventLoop',
    'function:readMessageString'
  ]) {
    assert(operation(thread, operationId).evidenceIds.includes('test:thread-event-loop-lifecycle'),
      `sys.thread.Thread.${operationId} must own executable lifecycle evidence`)
  }
  const createMutex = operation(mutexes, 'function:create')
  assert(createMutex.typeReferences.includes('rust.HxRef'), 'operation references must resolve imported public types')
  assert(createMutex.typeReferences.includes('rust.concurrent.Mutex'), 'operation references must resolve same-package public types')
  assert(mutexes.transitiveTypeReferences.includes('hxrt.concurrent.MutexHandle'),
    'type references must include the complete transitive package closure')
  const sliceTools = canonical.haxeTypes.find((entry) => entry.name === 'rust.SliceTools')
  assert(!sliceTools.operations.some((entry) => entry.id === 'function:toArray@2'),
    'macro-typing stubs must not become duplicate public operations')
  assert.match(operation(sliceTools, 'function:toArray').signature, /@:rustGeneric/,
    'conditional deduplication must retain the richer target metadata contract')

  const surface = checkerModule.discoverHaxeSurface([fixtureRoot])
  const sample = surface.find((entry) => entry.name === 'fixture.Surface')
  assert(sample, 'fixture class must be discovered')
  assert.match(sample.signature, /T : ParentContract/, 'generic constraints must be normalized into the type signature')
  assert.match(operation(sample, 'constructor:new').signature, /label : String = "fixture"/,
    'constructor defaults must be protected')
  assert.match(operation(sample, 'function:map').signature, /U : ParentContract/,
    'method generic constraints must be protected')
  assert.match(operation(sample, 'function:records').signature, /Array < \{label : String, value : T\} >/,
    'anonymous structures nested in generic return types must remain in the signature')
  assert.doesNotMatch(operation(sample, 'function:nested').signature, /afterNested/,
    'nested generic closers must not cause one operation to consume the next declaration')
  operation(sample, 'function:afterNested')
  assert(!sample.operations.some((entry) => entry.id.includes('hidden')), 'private members must not become public contracts')
  const structuralConstraint = surface.find((entry) => entry.name === 'fixture.Surface.StructuralConstraint')
  assert.match(structuralConstraint.signature, /T : \{\}/, 'structural generic constraints must not be mistaken for a type body')
  operation(structuralConstraint, 'function:accept')
  const conditionalSurface = surface.find((entry) => entry.name === 'fixture.Surface.ConditionalSurface')
  assert.deepStrictEqual(conditionalSurface.operations.map((entry) => entry.id), ['function:value'],
    'equivalent macro/runtime declarations must collapse to one public operation')
  assert.doesNotMatch(operation(conditionalSurface, 'function:value').signature, /return/,
    'expression-bodied implementation tokens must not leak into a public signature')

  const hxRef = canonical.haxeTypes.find((entry) => entry.name === 'rust.HxRef')
  assert.strictEqual(hxRef.contract, 'rust-hxref', 'rust.HxRef must use the explicit opaque-handle contract')
  const hxRefContract = canonical.contracts.find((entry) => entry.id === hxRef.contract)
  assert.strictEqual(hxRefContract.class, 'qualified-stable-candidate')
  assert(hxRefContract.exclusions.some((value) => value.includes('Arc/HxCell')), 'HxRef representation must remain non-contractual')

  const rustAsyncContract = canonical.contracts.find((entry) => entry.id === 'rust-async')
  assert.strictEqual(rustAsyncContract.class, 'experimental',
    'rust_async must remain outside the stable-major contract until task lifecycle semantics are owned')
  assert.strictEqual(rustAsyncContract.admission, 'experimental',
    'rust_async must not become a stable-admission candidate from codegen coverage alone')
  for (const excludedLifecycle of [
    'task panic and Haxe-throw mapping',
    'cancellation, join, drop, shutdown, and resource release',
    'bounded worker and thread ownership',
    'nested runtime behavior',
    'runtime-adapter isolation'
  ]) {
    assert(rustAsyncContract.exclusions.includes(excludedLifecycle),
      `the experimental rust_async contract must name the unowned lifecycle boundary: ${excludedLifecycle}`)
  }
  const rustAsyncTypes = canonical.haxeTypes.filter((entry) => entry.contract === 'rust-async')
  assert.deepStrictEqual(rustAsyncTypes.map((entry) => entry.name), [
    'rust.async.Async',
    'rust.async.Future',
    'rust.async.Task',
    'rust.async.Tasks',
    'rust.async.TokioRuntime'
  ], 'every shipped rust.async type must stay under the experimental family contract')
  for (const metadataName of ['async', 'await', 'rustAsync', 'rustAwait']) {
    const metadata = canonical.metadata.find((entry) => entry.name === metadataName)
    assert.strictEqual(metadata.contract, 'metadata-experimental',
      `@:${metadataName} must stay experimental with the async lifecycle it enables`)
  }
  assert.strictEqual(canonical.defines.find((entry) => entry.name === 'rust_async').contract, 'build-experimental',
    'the rust_async build switch must stay experimental with the surface it enables')

  const rustMetal = canonical.metadata.find((entry) => entry.name === 'rustMetal')
  assert.strictEqual(rustMetal.contract, 'metadata-stable', '@:rustMetal must be the canonical stable metal-island metadata')
  const haxeMetal = canonical.metadata.find((entry) => entry.name === 'haxeMetal')
  assert.strictEqual(haxeMetal.contract, 'haxe-metal-alias', '@:haxeMetal must remain a compatibility alias')
  const haxeMetalAlias = canonical.contracts.find((entry) => entry.id === haxeMetal.contract)
  assert.strictEqual(haxeMetalAlias.class, 'stable-candidate')
  assert.strictEqual(haxeMetalAlias.status, 'deprecated')
  assert(haxeMetalAlias.qualification.includes('rustMetal'), 'the alias contract must name @:rustMetal as the replacement')

  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haxe-rust-public-compat-'))
  try {
    const manifest = canonical

    const invalidClass = structuredClone(manifest)
    invalidClass.contracts[0].class = 'stable candidate for documented operations'
    const invalidClassPath = path.join(root, 'invalid-class.json')
    writeJson(invalidClassPath, invalidClass)
    expectFailure(run(['--manifest', invalidClassPath, '--skip-doc']), /noncanonical compatibility class/)

    const missingType = structuredClone(manifest)
    const removed = missingType.haxeTypes.shift()
    const missingTypePath = path.join(root, 'missing-type.json')
    writeJson(missingTypePath, missingType)
    expectFailure(run(['--manifest', missingTypePath, '--skip-doc']), new RegExp(`unclassified Haxe type.*${removed.name.replaceAll('.', '\\.')}`, 's'))

    const duplicateType = structuredClone(manifest)
    duplicateType.haxeTypes.push(structuredClone(duplicateType.haxeTypes[0]))
    const duplicateTypePath = path.join(root, 'duplicate-type.json')
    writeJson(duplicateTypePath, duplicateType)
    expectFailure(run(['--manifest', duplicateTypePath, '--skip-doc']), /duplicate Haxe type/)

    const missingOperation = structuredClone(manifest)
    const missingOperationOwner = missingOperation.haxeTypes.find((entry) => entry.name === 'rust.Result')
    missingOperationOwner.operations = missingOperationOwner.operations.filter((entry) => entry.id !== 'enum-constructor:Ok')
    const missingOperationPath = path.join(root, 'missing-operation.json')
    writeJson(missingOperationPath, missingOperation)
    expectFailure(run(['--manifest', missingOperationPath, '--skip-doc']), /operation graph drift.*rust\.Result.*enum-constructor:Ok/s)

    const changedSignature = structuredClone(manifest)
    operation(changedSignature.haxeTypes.find((entry) => entry.name === 'rust.concurrent.Mutexes'), 'function:create').signature += ' changed'
    const changedSignaturePath = path.join(root, 'changed-signature.json')
    writeJson(changedSignaturePath, changedSignature)
    expectFailure(run(['--manifest', changedSignaturePath, '--skip-doc']), /operation signature drift.*rust\.concurrent\.Mutexes.*function:create/s)

    const changedGenericDefault = structuredClone(manifest)
    changedGenericDefault.haxeTypes.find((entry) => entry.name === 'rust.Result').signature = 'enum Result < T , E = Dynamic >'
    const changedGenericDefaultPath = path.join(root, 'changed-generic-default.json')
    writeJson(changedGenericDefaultPath, changedGenericDefault)
    expectFailure(run(['--manifest', changedGenericDefaultPath, '--skip-doc']), /type signature drift.*rust\.Result/s)

    const changedGenericBound = structuredClone(manifest)
    const enumValueMap = changedGenericBound.haxeTypes.find((entry) => entry.name === 'haxe.ds.EnumValueMap')
    enumValueMap.signature = enumValueMap.signature.replace('K : EnumValue', 'K : Dynamic')
    const changedGenericBoundPath = path.join(root, 'changed-generic-bound.json')
    writeJson(changedGenericBoundPath, changedGenericBound)
    expectFailure(run(['--manifest', changedGenericBoundPath, '--skip-doc']), /type signature drift.*haxe\.ds\.EnumValueMap/s)

    const changedConstructorDefault = structuredClone(manifest)
    const elasticPool = changedConstructorDefault.haxeTypes.find((entry) => entry.name === 'sys.thread.ElasticThreadPool')
    operation(elasticPool, 'constructor:new').signature = operation(elasticPool, 'constructor:new').signature.replace('60', '61')
    const changedConstructorDefaultPath = path.join(root, 'changed-constructor-default.json')
    writeJson(changedConstructorDefaultPath, changedConstructorDefault)
    expectFailure(run(['--manifest', changedConstructorDefaultPath, '--skip-doc']), /operation signature drift.*sys\.thread\.ElasticThreadPool.*constructor:new/s)

    const changedTransitiveType = structuredClone(manifest)
    const changedMutexes = changedTransitiveType.haxeTypes.find((entry) => entry.name === 'rust.concurrent.Mutexes')
    changedMutexes.transitiveTypeReferences = changedMutexes.transitiveTypeReferences.filter((entry) => entry !== 'hxrt.concurrent.MutexHandle')
    const changedTransitiveTypePath = path.join(root, 'changed-transitive-type.json')
    writeJson(changedTransitiveTypePath, changedTransitiveType)
    expectFailure(run(['--manifest', changedTransitiveTypePath, '--skip-doc']), /transitive type-reference drift.*rust\.concurrent\.Mutexes/s)

    const publicizedInternal = structuredClone(manifest)
    publicizedInternal.haxeTypes.find((entry) => entry.name === 'hxrt.sys.NativeSys').contract = 'portable-sys-core'
    const publicizedInternalPath = path.join(root, 'publicized-internal.json')
    writeJson(publicizedInternalPath, publicizedInternal)
    expectFailure(run(['--manifest', publicizedInternalPath, '--skip-doc']), /internal application namespace.*internal-helper.*hxrt\.sys\.NativeSys/s)

    const unsealedInternal = structuredClone(manifest)
    unsealedInternal.haxeTypes.find((entry) => entry.name === 'Sys').contract = 'internal-helper'
    const unsealedInternalPath = path.join(root, 'unsealed-internal.json')
    writeJson(unsealedInternalPath, unsealedInternal)
    expectFailure(run(['--manifest', unsealedInternalPath, '--skip-doc']), /internal-helper type is not sealed.*Sys/s)

    const missingEvidence = structuredClone(manifest)
    missingEvidence.evidence.find((entry) => entry.kind === 'file').path = 'test/does-not-exist.compatibility-evidence'
    const missingEvidencePath = path.join(root, 'missing-evidence.json')
    writeJson(missingEvidencePath, missingEvidence)
    expectFailure(run(['--manifest', missingEvidencePath, '--skip-doc']), /evidence path does not exist/)

    const invalidPromotion = structuredClone(manifest)
    const experimental = invalidPromotion.contracts.find((entry) => entry.class === 'experimental')
    experimental.class = 'stable-candidate'
    const invalidPromotionPath = path.join(root, 'invalid-promotion.json')
    writeJson(invalidPromotionPath, invalidPromotion)
    expectFailure(run(['--manifest', invalidPromotionPath, '--skip-doc']), /admission state.*incompatible.*stable-candidate/)

    const familyOnlyAdmission = structuredClone(manifest)
    familyOnlyAdmission.evidence.push({
      id: 'test:synthetic-semantic-admission',
      kind: 'npm-script',
      script: 'test:public-compatibility',
      level: 'semantic-runtime'
    })
    familyOnlyAdmission.evidence.push({
      id: 'bead:haxe_rust-p6hs.2',
      kind: 'bead',
      bead: 'haxe_rust-p6hs.2',
      level: 'review-record'
    })
    const admittedValues = familyOnlyAdmission.contracts.find((entry) => entry.id === 'rust-values-core')
    admittedValues.admission = 'admitted'
    admittedValues.admissionRecord = 'bead:haxe_rust-p6hs.2'
    admittedValues.evidenceIds.push('test:synthetic-semantic-admission')
    const familyOnlyAdmissionPath = path.join(root, 'family-only-admission.json')
    writeJson(familyOnlyAdmissionPath, familyOnlyAdmission)
    expectFailure(run(['--manifest', familyOnlyAdmissionPath, '--skip-doc']), /operation rust\.(?:Option|Result).*lacks operation-specific executable evidence/s)

    const leakingAdmission = structuredClone(manifest)
    leakingAdmission.evidence.push({
      id: 'test:synthetic-transitive-admission',
      kind: 'npm-script',
      script: 'test:public-compatibility',
      level: 'target-runtime'
    })
    leakingAdmission.evidence.push({
      id: 'bead:haxe_rust-p6hs.3',
      kind: 'bead',
      bead: 'haxe_rust-p6hs.3',
      level: 'review-record'
    })
    const admittedConcurrency = leakingAdmission.contracts.find((entry) => entry.id === 'rust-concurrency')
    admittedConcurrency.admission = 'admitted'
    admittedConcurrency.admissionRecord = 'bead:haxe_rust-p6hs.3'
    admittedConcurrency.evidenceIds.push('test:synthetic-transitive-admission')
    for (const type of leakingAdmission.haxeTypes.filter((entry) => entry.contract === 'rust-concurrency')) {
      type.evidenceIds.push('test:synthetic-transitive-admission')
      for (const member of type.operations.filter((entry) => entry.contract === 'rust-concurrency')) {
        member.evidenceIds.push('test:synthetic-transitive-admission')
      }
    }
    const leakingAdmissionPath = path.join(root, 'leaking-admission.json')
    writeJson(leakingAdmissionPath, leakingAdmission)
    expectFailure(run(['--manifest', leakingAdmissionPath, '--skip-doc']), /admitted (?:type|operation).*transitive public type.*hxrt\.concurrent\..*internal/s)

    const invalidDeprecation = structuredClone(manifest)
    delete invalidDeprecation.contracts.find((entry) => entry.id === 'haxe-metal-alias').deprecation.replacement
    const invalidDeprecationPath = path.join(root, 'invalid-deprecation.json')
    writeJson(invalidDeprecationPath, invalidDeprecation)
    expectFailure(run(['--manifest', invalidDeprecationPath, '--skip-doc']), /deprecated contract.*replacement/)

    const invalidMetadataGrammar = structuredClone(manifest)
    delete invalidMetadataGrammar.metadata.find((entry) => entry.name === 'rustTest').grammar
    const invalidMetadataGrammarPath = path.join(root, 'invalid-metadata-grammar.json')
    writeJson(invalidMetadataGrammarPath, invalidMetadataGrammar)
    expectFailure(run(['--manifest', invalidMetadataGrammarPath, '--skip-doc']), /metadata rustTest must declare grammar/)

    const invalidDefineDefault = structuredClone(manifest)
    delete invalidDefineDefault.defines.find((entry) => entry.name === 'reflaxe_rust_profile').default
    const invalidDefineDefaultPath = path.join(root, 'invalid-define-default.json')
    writeJson(invalidDefineDefaultPath, invalidDefineDefault)
    expectFailure(run(['--manifest', invalidDefineDefaultPath, '--skip-doc']), /define reflaxe_rust_profile must declare default/)

    const refreshedOnce = checkerModule.refreshManifest(structuredClone(canonical))
    const refreshedTwice = checkerModule.refreshManifest(structuredClone(refreshedOnce))
    assert.deepStrictEqual(refreshedTwice, refreshedOnce, 'surface generation must converge byte-for-byte after one refresh')

    const first = run(['--render'])
    const second = run(['--render'])
    assert.strictEqual(first.status, 0, first.stderr)
    assert.strictEqual(second.status, 0, second.stderr)
    assert.strictEqual(first.stdout, second.stdout, 'generated compatibility summary must be byte-for-byte repeatable')
  } finally {
    fs.rmSync(root, { recursive: true, force: true })
  }

  console.log('[public-compatibility-manifest-test] OK')
}

main()
