package rust;

/**
 * rust.Option<T>
 *
 * Explicit Rust-facing option type for the `rusty` profile.
 *
 * Codegen maps this to Rust's built-in `Option<T>` (and does not emit a Rust enum for it).
 */
enum Option<T> {
	Some(value: T);
	None;
}

