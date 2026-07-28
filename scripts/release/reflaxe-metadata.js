function normalizedRepository(value) {
  if (typeof value !== 'string' || value.length === 0) return ''
  return value.replace(/\/+$/, '').replace(/\.git$/, '')
}

function requireNonEmptyString(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`${label} must be a non-empty string`)
  }
  return value
}

/**
 * Why
 * The vendored framework ships both Haxelib metadata and a detailed source
 * record. Package tools may read either file, so they must not disagree about
 * which project this is or which license applies.
 *
 * What
 * Require the small Haxelib projection to identify Reflaxe and to repeat the
 * repository and license values owned by `provenance.json`.
 *
 * How
 * Compare the license exactly and compare repository URLs after removing only
 * an optional trailing slash or `.git` suffix.
 */
function validateReflaxeHaxelib(provenance, haxelib) {
  if (provenance?.component?.name !== 'Reflaxe') {
    throw new Error('Reflaxe provenance component name must be Reflaxe')
  }
  if (haxelib?.name !== 'reflaxe') {
    throw new Error('Reflaxe haxelib metadata contradicts provenance: name must be reflaxe')
  }
  const provenanceLicense = requireNonEmptyString(
    provenance?.component?.license,
    'Reflaxe provenance license'
  )
  const haxelibLicense = requireNonEmptyString(
    haxelib.license,
    'Reflaxe haxelib license'
  )
  if (haxelibLicense !== provenanceLicense) {
    throw new Error('Reflaxe haxelib metadata contradicts provenance: license differs')
  }
  const provenanceRepository = requireNonEmptyString(
    provenance?.component?.upstreamRepository,
    'Reflaxe provenance repository'
  )
  const haxelibRepository = requireNonEmptyString(
    haxelib.url,
    'Reflaxe haxelib repository'
  )
  if (
    normalizedRepository(haxelibRepository) !==
    normalizedRepository(provenanceRepository)
  ) {
    throw new Error('Reflaxe haxelib metadata contradicts provenance: repository differs')
  }
}

module.exports = { normalizedRepository, requireNonEmptyString, validateReflaxeHaxelib }
