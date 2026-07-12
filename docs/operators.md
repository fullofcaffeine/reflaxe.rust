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
`Array<String>` elements also support append assignment (`values[index] += suffix`). Compound
assignment resolves the array, index, and current element before evaluating the RHS, evaluates each
source expression once, and preserves Haxe's assigned-value result through the existing typed array
get/set contract. Statement-position String append moves the new value directly into the array;
expression position clones only because both the array and expression result need ownership.

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

Static accessor properties (`static var value(get,set)`) remain distinct from raw static storage.
Haxe's typed AST supplies `get_value` / `set_value` calls for ordinary, compound, prefix/postfix, and
String-append updates, including the setter's returned expression value.

Current limitation: compound assignment support is still conservative for some complex lvalues,
especially non-Copy array-element operations other than String append and anonymous-object fields.

Fields reached through a `Dynamic` receiver support ordinary runtime get/set, but not compound
assignment or prefix/postfix updates. Their payload type is known only at runtime, so silently
assuming `Int`, `Float`, or `String` would be unsound and a general runtime dynamic-operator layer is
outside the admitted contract. Decode to a typed structure at the boundary, or perform an explicit
`Reflect.field` / typed conversion / `Reflect.setField` sequence when the field is genuinely dynamic.
The compiler reports this boundary as `[HXRS-DYNAMIC-FIELD-OPERATOR]` at the user expression.

## Snapshot coverage

See:

- `test/snapshot/mod_bitwise`
- `test/snapshot/array_assignop_index`
- `test/snapshot/class_string_field_assignop`
- `test/semantic_diff/array_index_updates`
- `test/semantic_diff/array_string_element_append`
- `test/semantic_diff/polymorphic_field_updates`
- `test/semantic_diff/static_property_updates`
- `test/semantic_diff/static_field_updates`
