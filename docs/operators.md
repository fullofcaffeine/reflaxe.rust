# Numeric Operators (Rust target)

This target lowers Haxe numeric operators to Rust operators with a few target-specific notes.

## Supported (Int / `i32`)

- `%` (`OpMod`) → `%`
- `&` (`OpAnd`) → `&`
- `|` (`OpOr`) → `|`
- `^` (`OpXor`) → `^`
- `<<` (`OpShl`) → `<<`
- `>>` (`OpShr`) → `>>` (arithmetic shift on `i32`)
- `>>>` (`OpUShr`) → logical shift implemented as `((x as u32) >> (y as u32)) as i32`
- `~x` (`OpNegBits`) → `!x`

## Compound assignments

Compound assignments for locals are supported (e.g. `x += y`, `x %= y`, `x <<= 1`).

Current limitation: compound assignment support is conservative for complex lvalues (fields / array indices).

## Snapshot coverage

See `test/snapshot/mod_bitwise`.

