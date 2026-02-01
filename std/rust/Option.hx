package rust;

/**
 * rust.Option<T>
 *
 * Why:
 * - Portable Haxe optionality is typically modeled with `Null<T>`.
 * - In Rusty-profile code we often want *explicit* Rust semantics: `Option<T>` for “maybe a value”.
 *
 * What:
 * - A Rust-facing `Option<T>` surface in Haxe syntax.
 *
 * How:
 * - The compiler treats `rust.Option<T>` as a **builtin enum** and maps it directly to Rust's
 *   `Option<T>` (it does not emit a Rust enum for this type).
 * - Pattern matching works as expected:
 *   - `Some(v)` ↔ `Option::Some(v)`
 *   - `None`    ↔ `Option::None`
 *
 * Notes:
 * - Prefer using helper methods from `rust.OptionTools` (`map`, `andThen`, `okOrElse`, etc.) instead
 *   of writing `switch` blocks everywhere.
 *
 * Related:
 * - `rust.Result<T,E>` for fallible operations.
 */
enum Option<T> {
	Some(value: T);
	None;
}
