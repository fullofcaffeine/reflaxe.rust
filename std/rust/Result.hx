package rust;

/**
 * rust.Result<T, E>
 *
 * Why:
 * - Portable Haxe error handling commonly uses exceptions (`throw` / `try/catch`).
 * - In Rusty-profile code we often want *explicit* Rust semantics: `Result<T,E>` for fallible APIs.
 *
 * What:
 * - A Rust-facing `Result<T, E>` surface in Haxe syntax.
 *
 * How:
 * - The compiler treats `rust.Result<T,E>` as a **builtin enum** and maps it directly to Rust's
 *   `Result<T,E>` (it does not emit a Rust enum for this type).
 * - Pattern matching works as expected:
 *   - `Ok(v)`   ↔ `Result::Ok(v)`
 *   - `Err(e)`  ↔ `Result::Err(e)`
 *
 * Notes:
 * - Use `rust.ResultTools` for ergonomic composition (`mapOk`, `mapErr`, `andThen`, `context`, etc.).
 * - The default error type is `String` to make quick Rusty APIs easy to write, but prefer a richer
 *   error enum once your API stabilizes.
 *
 * Related:
 * - `rust.Option<T>` for “maybe a value”.
 */
enum Result<T, E = String> {
	Ok(value: T);
	Err(error: E);
}
