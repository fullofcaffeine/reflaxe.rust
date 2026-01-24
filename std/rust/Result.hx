package rust;

/**
 * rust.Result<T, E>
 *
 * Explicit Rust-facing result type for the `rusty` profile.
 *
 * Codegen maps this to Rust's built-in `Result<T, E>` (and does not emit a Rust enum for it).
 */
enum Result<T, E = String> {
	Ok(value: T);
	Err(error: E);
}

