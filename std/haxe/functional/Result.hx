package haxe.functional;

/**
 * Result<T, E> algebraic data type for typed error handling.
 *
 * NOTE (reflaxe.rust):
 * - This enum exists at typing time for portable Haxe code.
 * - Codegen maps it to Rust's built-in `Result<T, E>`, translating:
 *   - `Ok(v)` -> `Result::Ok(v)`
 *   - `Error(e)` -> `Result::Err(e)`
 */
enum Result<T, E = String> {
	Ok(value: T);
	Error(error: E);
}

