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

Copy-like numeric array elements support compound assignment plus prefix/postfix `++` and `--`.
Array and index expressions are evaluated once, and updates preserve Haxe's assigned/old/new
expression results through the existing typed array get/set contract.

Class field compound assignments are supported for Copy-like numeric values and for `String` append
(`field += value`). String field append evaluates the RHS before taking the mutable field borrow,
formats from an immutable field borrow, writes the new value, and returns the assigned value.

The same operations work through a base-typed polymorphic reference. Because that Rust value is a
trait object rather than the concrete child storage, lowering evaluates the receiver and RHS once,
then uses the generated typed field getter and setter. Numeric prefix/postfix `++` and `--` preserve
Haxe's new-value/old-value expression results through this path as well.

Mutable static fields use the same semantic contract through their generated lazy-cell getter and
setter functions. Copy-like numeric compound assignments, numeric prefix/postfix `++` and `--`, and
`String +=` evaluate the RHS once and return the Haxe assigned/old/new expression value.

Current limitation: compound assignment support is still conservative for some complex lvalues,
especially non-Copy array indices and anonymous-object fields.

## Snapshot coverage

See:

- `test/snapshot/mod_bitwise`
- `test/snapshot/array_assignop_index`
- `test/snapshot/class_string_field_assignop`
- `test/semantic_diff/array_index_updates`
- `test/semantic_diff/polymorphic_field_updates`
- `test/semantic_diff/static_field_updates`
