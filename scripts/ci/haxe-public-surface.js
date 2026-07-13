#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

const TYPE_KEYWORDS = new Set(['class', 'interface', 'abstract', 'enum', 'typedef'])
const TYPE_REFERENCE_KEYWORDS = new Set([
  'abstract', 'as', 'break', 'case', 'cast', 'catch', 'class', 'continue', 'default',
  'do', 'dynamic', 'else', 'enum', 'extends', 'extern', 'false', 'final', 'for',
  'from', 'function', 'if', 'implements', 'import', 'in', 'inline', 'interface',
  'macro', 'new', 'never', 'null', 'operator', 'override', 'package', 'private',
  'public', 'return', 'static', 'super', 'switch', 'this', 'throw', 'to', 'true',
  'typedef', 'untyped', 'using', 'var', 'while'
])

/**
 * Why: the compatibility guard must run before the Haxe toolchain is installed in CI and must
 * describe declarations that are shipped but not necessarily loaded by one compiler invocation.
 * What: a deliberately small lexical scanner for public Haxe declaration shapes.
 * How: comments, bodies, and preprocessor directive lines are ignored; type/member headers remain
 * tokenized, balanced, normalized, and compared byte-for-byte. This is a source-contract scanner,
 * not a replacement for Haxe typing or semantic evidence.
 */
function tokenize(source) {
  const tokens = []
  const multi = ['>>>', '...', '=>', '->', '@:', '?.', '??', '++', '--', '&&', '||', '==', '!=', '<=', '>=', '<<', '>>', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=']
  let index = 0
  let lineStart = true

  while (index < source.length) {
    const ch = source[index]
    if (ch === '\n' || ch === '\r') {
      lineStart = true
      index += 1
      continue
    }
    if (/\s/.test(ch)) {
      index += 1
      continue
    }
    if (lineStart && ch === '#') {
      while (index < source.length && source[index] !== '\n') index += 1
      continue
    }
    lineStart = false
    if (source.startsWith('//', index)) {
      while (index < source.length && source[index] !== '\n') index += 1
      continue
    }
    if (source.startsWith('/*', index)) {
      index += 2
      while (index < source.length && !source.startsWith('*/', index)) index += 1
      index = Math.min(source.length, index + 2)
      continue
    }
    if (ch === '"' || ch === "'") {
      const quote = ch
      const start = index
      index += 1
      while (index < source.length) {
        if (source[index] === '\\') {
          index += 2
          continue
        }
        if (source[index] === quote) {
          index += 1
          break
        }
        index += 1
      }
      tokens.push(source.slice(start, index))
      continue
    }
    const identifier = source.slice(index).match(/^[A-Za-z_$][A-Za-z0-9_$]*/)
    if (identifier != null) {
      tokens.push(identifier[0])
      index += identifier[0].length
      continue
    }
    const number = source.slice(index).match(/^(?:0[xX][0-9A-Fa-f]+|0[bB][01]+|[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)/)
    if (number != null) {
      tokens.push(number[0])
      index += number[0].length
      continue
    }
    const operator = multi.find((value) => source.startsWith(value, index))
    if (operator != null) {
      tokens.push(operator)
      index += operator.length
      continue
    }
    tokens.push(ch)
    index += 1
  }
  return tokens
}

function filesUnder(root) {
  const result = []
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name)
      if (entry.isDirectory()) visit(full)
      else if (entry.isFile() && full.endsWith('.hx')) result.push(full)
    }
  }
  if (fs.existsSync(root)) visit(root)
  return result.sort()
}

function matchingBrace(tokens, openIndex, open = '{', close = '}') {
  let depth = 0
  for (let index = openIndex; index < tokens.length; index += 1) {
    if (tokens[index] === open) depth += 1
    else if (tokens[index] === close) {
      depth -= 1
      if (depth === 0) return index
    }
  }
  return -1
}

function normalized(tokens) {
  return tokens.join(' ')
    .replace(/\s+([,;)\]}])/g, '$1')
    .replace(/([([{])\s+/g, '$1')
    .replace(/\s+\.\s+/g, '.')
    .replace(/@:\s+/g, '@:')
    .trim()
}

function adjustedAngleDepth(depth, token) {
  if (token === '<') return depth + 1
  if (token === '>') return Math.max(0, depth - 1)
  if (token === '>>') return Math.max(0, depth - 2)
  if (token === '>>>') return Math.max(0, depth - 3)
  return depth
}

function packageName(tokens) {
  const index = tokens.indexOf('package')
  if (index < 0) return ''
  const parts = []
  for (let cursor = index + 1; cursor < tokens.length && tokens[cursor] !== ';'; cursor += 1) {
    if (tokens[cursor] !== '.') parts.push(tokens[cursor])
  }
  return parts.join('.')
}

function imports(tokens) {
  const result = new Map()
  for (let index = 0; index < tokens.length; index += 1) {
    if (tokens[index] !== 'import') continue
    const values = []
    let alias = null
    index += 1
    while (index < tokens.length && tokens[index] !== ';') {
      if (tokens[index] === 'as' && index + 1 < tokens.length) {
        alias = tokens[index + 1]
        index += 2
        continue
      }
      values.push(tokens[index])
      index += 1
    }
    const imported = values.join('').replace(/\.\*$/, '')
    if (imported.length === 0 || imported.endsWith('.')) continue
    const local = alias || imported.split('.').at(-1)
    result.set(local, imported)
  }
  return result
}

function typeParameterNames(header, nameIndex) {
  const names = new Set()
  if (header[nameIndex + 1] !== '<') return names
  let depth = 0
  let expectName = true
  for (let index = nameIndex + 1; index < header.length; index += 1) {
    const token = header[index]
    if (token === '<') {
      depth = adjustedAngleDepth(depth, token)
      if (depth === 1) expectName = true
      continue
    }
    if (token === '>' || token === '>>' || token === '>>>') {
      depth = adjustedAngleDepth(depth, token)
      if (depth === 0) break
      continue
    }
    if (depth === 1 && token === ',') {
      expectName = true
      continue
    }
    if (depth === 1 && expectName && /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(token)) {
      names.add(token)
      expectName = false
    }
  }
  return names
}

function memberGenericNames(signature) {
  const names = new Set()
  const functionIndex = signature.indexOf('function')
  if (functionIndex < 0) return names
  return typeParameterNames(signature, functionIndex + 1)
}

function operationId(operations, base) {
  if (!operations.some((entry) => entry.id === base)) return base
  let suffix = 2
  while (operations.some((entry) => entry.id === `${base}@${suffix}`)) suffix += 1
  return `${base}@${suffix}`
}

function callableShape(signature, kind) {
  if (kind !== 'function' && kind !== 'constructor') return signature
  for (const marker of ['public ', 'function ']) {
    const index = signature.indexOf(marker)
    if (index >= 0) return signature.slice(index)
  }
  return signature
}

function pushOperation(operations, base, operation) {
  const equivalent = operations.find((entry) => entry.kind === operation.kind && entry.name === operation.name && callableShape(entry.signature, entry.kind) === callableShape(operation.signature, operation.kind))
  if (equivalent != null) {
    // Conditional macro-typing stubs often repeat the callable Haxe shape without target metadata.
    // Keep the richer declaration so bounds/lowering metadata remain protected, but do not invent
    // a public overload that consumers cannot actually select.
    if (operation.signature.length > equivalent.signature.length) {
      const id = equivalent.id
      Object.assign(equivalent, operation, { id })
    }
    return
  }
  operations.push({ ...operation, id: operationId(operations, base) })
}

function isPublic(prefix, kind) {
  if (prefix.includes('private')) return false
  return prefix.includes('public') || kind === 'interface' || kind === 'typedef' || kind === 'enum-abstract'
}

function functionEnd(tokens, functionIndex, limit) {
  const params = tokens.indexOf('(', functionIndex + 1)
  if (params < 0 || params >= limit) return { signatureEnd: limit, next: limit }
  const paramsEnd = matchingBrace(tokens, params, '(', ')')
  if (paramsEnd < 0) return { signatureEnd: limit, next: limit }
  let index = paramsEnd + 1
  const hasReturnType = tokens[index] === ':'
  let returnTypeTokens = 0
  let angleDepth = 0
  while (index < limit) {
    if (tokens[index] === ';') return { signatureEnd: index, next: index + 1 }
    if (tokens[index] === 'return' || tokens[index] === 'throw') {
      const expressionEnd = fieldEnd(tokens, index, limit)
      return { signatureEnd: index, next: expressionEnd < limit ? expressionEnd + 1 : limit }
    }
    if (hasReturnType) angleDepth = adjustedAngleDepth(angleDepth, tokens[index])
    if (tokens[index] === '{') {
      // A return type can itself contain an anonymous structure, either directly (`:{...}`) or
      // nested under a generic (`:Array<{...}>`). Only the next top-level brace after the complete
      // return type begins the function body.
      if (hasReturnType && (returnTypeTokens === 0 || angleDepth > 0)) {
        const typeEnd = matchingBrace(tokens, index)
        if (typeEnd < 0) return { signatureEnd: limit, next: limit }
        returnTypeTokens += typeEnd - index + 1
        index = typeEnd + 1
        continue
      }
      const bodyEnd = matchingBrace(tokens, index)
      return { signatureEnd: index, next: bodyEnd < 0 ? limit : bodyEnd + 1 }
    }
    if (hasReturnType && tokens[index] !== ':') returnTypeTokens += 1
    index += 1
  }
  return { signatureEnd: limit, next: limit }
}

function fieldEnd(tokens, start, limit) {
  let braces = 0
  let brackets = 0
  let parentheses = 0
  for (let index = start; index < limit; index += 1) {
    if (tokens[index] === '{') braces += 1
    else if (tokens[index] === '}') braces -= 1
    else if (tokens[index] === '[') brackets += 1
    else if (tokens[index] === ']') brackets -= 1
    else if (tokens[index] === '(') parentheses += 1
    else if (tokens[index] === ')') parentheses -= 1
    else if (tokens[index] === ';' && braces === 0 && brackets === 0 && parentheses === 0) return index
  }
  return limit
}

function discoverMembers(tokens, start, end, kind) {
  const operations = []
  if (kind === 'enum') {
    let segmentStart = start
    let braces = 0
    let parentheses = 0
    let brackets = 0
    for (let index = start; index <= end; index += 1) {
      const token = tokens[index]
      if (token === '{') braces += 1
      else if (token === '}') braces -= 1
      else if (token === '(') parentheses += 1
      else if (token === ')') parentheses -= 1
      else if (token === '[') brackets += 1
      else if (token === ']') brackets -= 1
      if ((token === ';' || index === end) && braces === 0 && parentheses === 0 && brackets === 0) {
        const segment = tokens.slice(segmentStart, token === ';' ? index : index + 1)
        let constructor = null
        for (let cursor = 0; cursor < segment.length; cursor += 1) {
          if (segment[cursor] === '@:') {
            cursor += 1
            if (segment[cursor + 1] === '(') cursor = matchingBrace(segment, cursor + 1, '(', ')')
            continue
          }
          if (/^[A-Z_$][A-Za-z0-9_$]*$/.test(segment[cursor])) {
            constructor = segment[cursor]
            break
          }
        }
        if (constructor != null) {
          pushOperation(operations, `enum-constructor:${constructor}`, {
            kind: 'enum-constructor',
            name: constructor,
            signature: normalized(segment),
            signatureTokens: segment
          })
        }
        segmentStart = index + 1
      }
    }
    return operations
  }

  let index = start
  let segmentStart = start
  while (index < end) {
    if (tokens[index] === ';') {
      segmentStart = index + 1
      index += 1
      continue
    }
    if (tokens[index] === 'function') {
      const name = tokens[index + 1]
      const prefix = tokens.slice(segmentStart, index)
      const boundary = functionEnd(tokens, index, end)
      if (typeof name === 'string' && isPublic(prefix, kind)) {
        const signatureTokens = tokens.slice(segmentStart, boundary.signatureEnd)
        const operationKind = name === 'new' ? 'constructor' : 'function'
        pushOperation(operations, `${operationKind}:${name}`, {
          kind: operationKind,
          name,
          signature: normalized(signatureTokens),
          signatureTokens
        })
      }
      index = boundary.next
      segmentStart = index
      continue
    }
    if (tokens[index] === 'var' || tokens[index] === 'final') {
      const keyword = tokens[index]
      const name = tokens[index + 1]
      const prefix = tokens.slice(segmentStart, index)
      const boundary = fieldEnd(tokens, index, end)
      if (typeof name === 'string' && isPublic(prefix, kind)) {
        const signatureTokens = tokens.slice(segmentStart, boundary)
        const operationKind = kind === 'enum-abstract' && keyword === 'var' ? 'enum-value' : 'field'
        pushOperation(operations, `${operationKind}:${name}`, {
          kind: operationKind,
          name,
          signature: normalized(signatureTokens),
          signatureTokens
        })
      }
      index = boundary + 1
      segmentStart = index
      continue
    }
    if (tokens[index] === '{') {
      const close = matchingBrace(tokens, index)
      index = close < 0 ? end : close + 1
      segmentStart = index
      continue
    }
    index += 1
  }
  return operations
}

function discoverFile(file) {
  const tokens = tokenize(fs.readFileSync(file, 'utf8'))
  const packagePath = packageName(tokens)
  const imported = imports(tokens)
  const moduleName = path.basename(file, '.hx')
  const declarations = []
  let depth = 0
  let boundary = 0

  for (let index = 0; index < tokens.length; index += 1) {
    if (tokens[index] === '{') {
      depth += 1
      continue
    }
    if (tokens[index] === '}') {
      depth -= 1
      if (depth === 0) boundary = index + 1
      continue
    }
    if (depth !== 0) continue
    if (tokens[index] === ';') {
      boundary = index + 1
      continue
    }
    if (!TYPE_KEYWORDS.has(tokens[index])) continue

    let kind = tokens[index]
    let nameIndex = index + 1
    if (tokens[index] === 'enum' && tokens[index + 1] === 'abstract') {
      kind = 'enum-abstract'
      nameIndex = index + 2
    }
    const name = tokens[nameIndex]
    if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name || '')) continue
    const prefix = tokens.slice(boundary, index)
    if (prefix.includes('private')) continue

    let bodyStart = -1
    let declarationEnd = -1
    let angleDepth = 0
    let parenthesesDepth = 0
    let bracketsDepth = 0
    for (let cursor = nameIndex + 1; cursor < tokens.length; cursor += 1) {
      angleDepth = adjustedAngleDepth(angleDepth, tokens[cursor])
      if (tokens[cursor] === '(') parenthesesDepth += 1
      else if (tokens[cursor] === ')') parenthesesDepth = Math.max(0, parenthesesDepth - 1)
      else if (tokens[cursor] === '[') bracketsDepth += 1
      else if (tokens[cursor] === ']') bracketsDepth = Math.max(0, bracketsDepth - 1)
      if (tokens[cursor] === '{') {
        if (angleDepth > 0 || parenthesesDepth > 0 || bracketsDepth > 0) {
          const typeBraceEnd = matchingBrace(tokens, cursor)
          if (typeBraceEnd < 0) break
          cursor = typeBraceEnd
          continue
        }
        bodyStart = cursor
        declarationEnd = matchingBrace(tokens, cursor)
        break
      }
      if (tokens[cursor] === ';' && angleDepth === 0 && parenthesesDepth === 0 && bracketsDepth === 0) {
        declarationEnd = cursor
        break
      }
    }
    if (declarationEnd < 0) continue
    const signatureEnd = bodyStart >= 0 ? bodyStart : declarationEnd
    const signatureTokens = tokens.slice(boundary, signatureEnd)
    const typeKeywordIndex = signatureTokens.lastIndexOf(tokens[index])
    const localNameIndex = signatureTokens.indexOf(name, Math.max(0, typeKeywordIndex + 1))
    const typeParameters = typeParameterNames(signatureTokens, localNameIndex)
    const prefixPath = packagePath.length > 0 ? `${packagePath}.` : ''
    const canonicalName = name === moduleName ? `${prefixPath}${name}` : `${prefixPath}${moduleName}.${name}`
    const operations = bodyStart >= 0
      ? discoverMembers(tokens, bodyStart + 1, declarationEnd, kind)
      : []
    declarations.push({
      name: canonicalName,
      moduleName,
      packageName: packagePath,
      sourceFile: file,
      kind,
      signature: normalized(signatureTokens),
      signatureTokens,
      typeParameters,
      imports: imported,
      operations
    })
    index = declarationEnd
    boundary = declarationEnd + 1
  }
  return declarations
}

function candidateReferences(tokens, owner, symbols, uniqueSimpleNames, localTypeParameters) {
  const references = new Set()
  const genericNames = new Set([...owner.typeParameters, ...localTypeParameters])
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index]
    if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(token) || TYPE_REFERENCE_KEYWORDS.has(token) || genericNames.has(token)) continue
    const pathParts = [token]
    let cursor = index
    while (tokens[cursor + 1] === '.' && /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(tokens[cursor + 2] || '')) {
      pathParts.push(tokens[cursor + 2])
      cursor += 2
    }
    const qualified = pathParts.join('.')
    let resolved = null
    if (symbols.has(qualified)) resolved = qualified
    else if (pathParts.length === 1 && owner.imports.has(token) && symbols.has(owner.imports.get(token))) resolved = owner.imports.get(token)
    else if (pathParts.length === 1 && owner.packageName.length > 0 && symbols.has(`${owner.packageName}.${token}`)) resolved = `${owner.packageName}.${token}`
    else if (pathParts.length === 1 && symbols.has(`${owner.packageName}.${owner.moduleName}.${token}`)) resolved = `${owner.packageName}.${owner.moduleName}.${token}`
    else if (pathParts.length === 1 && uniqueSimpleNames.has(token)) resolved = uniqueSimpleNames.get(token)
    if (resolved != null && resolved !== owner.name) references.add(resolved)
    index = cursor
  }
  return Array.from(references).sort()
}

function discoverHaxeSurface(roots, repoRoot = process.cwd()) {
  const discovered = roots.flatMap((root) => filesUnder(root).flatMap(discoverFile))
    .sort((left, right) => left.name.localeCompare(right.name))
  const names = new Set()
  for (const type of discovered) {
    if (names.has(type.name)) throw new Error(`duplicate discovered Haxe type: ${type.name}`)
    names.add(type.name)
  }
  const bySimpleName = new Map()
  for (const type of discovered) {
    const simple = type.name.split('.').at(-1)
    const current = bySimpleName.get(simple)
    bySimpleName.set(simple, current == null ? type.name : false)
  }
  const uniqueSimpleNames = new Map(Array.from(bySimpleName).filter(([, value]) => value !== false))
  for (const type of discovered) {
    type.directTypeReferences = candidateReferences(type.signatureTokens, type, names, uniqueSimpleNames, new Set())
    for (const operation of type.operations) {
      operation.typeReferences = candidateReferences(operation.signatureTokens, type, names, uniqueSimpleNames, memberGenericNames(operation.signatureTokens))
      delete operation.signatureTokens
    }
    for (const operation of type.operations) {
      for (const reference of operation.typeReferences) {
        if (!type.directTypeReferences.includes(reference)) type.directTypeReferences.push(reference)
      }
    }
    type.directTypeReferences.sort()
    delete type.signatureTokens
    delete type.typeParameters
    delete type.imports
    delete type.moduleName
    delete type.packageName
    type.source = path.relative(repoRoot, type.sourceFile).split(path.sep).join('/')
    delete type.sourceFile
  }
  const graph = new Map(discovered.map((entry) => [entry.name, entry.directTypeReferences]))
  for (const type of discovered) {
    const closure = new Set()
    const pending = [...type.directTypeReferences]
    while (pending.length > 0) {
      const next = pending.shift()
      if (closure.has(next) || next === type.name) continue
      closure.add(next)
      for (const child of graph.get(next) || []) pending.push(child)
    }
    type.transitiveTypeReferences = Array.from(closure).sort()
  }
  return discovered
}

module.exports = { discoverHaxeSurface, normalized, tokenize }
