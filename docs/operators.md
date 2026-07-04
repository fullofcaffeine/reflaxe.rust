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

Class field compound assignments are supported for Copy-like numeric values and for `String` append
(`field += value`). String field append evaluates the RHS before taking the mutable field borrow,
formats from an immutable field borrow, writes the new value, and returns the assigned value.

Current limitation: compound assignment support is still conservative for some complex lvalues,
especially non-Copy array indices and anonymous-object fields.

## Snapshot coverage

See:

- `test/snapshot/mod_bitwise`
- `test/snapshot/class_string_field_assignop`
