package rust.adapters;

/**
	Typed bridge between the planned portable idiom package (`reflaxe.std`) and Rust-native
	surfaces (`rust.Option`, `rust.Result`).

	Why
	- `reflaxe.std` is intended as the portable API surface shared across backends.
	- `rust.Option`/`rust.Result` remain explicit native APIs for Rust-first code.
	- Migration between both surfaces must be explicit and strongly typed, never hidden behind
	  profile switches or untyped conversion helpers.

	What
	- `toRustOption` / `fromRustOption` convert `reflaxe.std.Option<T>` <-> `rust.Option<T>`.
	- `toRustResult` / `fromRustResult` convert `reflaxe.std.Result<T,E>` <-> `rust.Result<T,E>`.

	How
	- Conversions are implemented as typed `cast` operations because both surfaces lower to the
	  same Rust representation (`Option<T>` / `Result<T,E>`).
	- The important distinction is authoring contract, not emitted runtime type:
	  `reflaxe.std.*` is the portable/shared API surface, while `rust.*` is the explicit Rust-native surface.
	- This keeps adapters zero-cost and avoids introducing extra `Clone` bounds on generic type
	  parameters.
	- No `Dynamic`/`Reflect` boundary is introduced.
	- This module intentionally depends on `reflaxe.std` types; projects that do not install
	  `reflaxe.std` should not import this bridge.
**/
class ReflaxeStdAdapters {
	/**
		Converts portable `reflaxe.std.Option<T>` to Rust-native `rust.Option<T>`.
	**/
	public static inline function toRustOption<T>(value:reflaxe.std.Option<T>):rust.Option<T> {
		return cast value;
	}

	/**
		Converts Rust-native `rust.Option<T>` to portable `reflaxe.std.Option<T>`.
	**/
	public static inline function fromRustOption<T>(value:rust.Option<T>):reflaxe.std.Option<T> {
		return cast value;
	}

	/**
		Converts portable `reflaxe.std.Result<T,E>` to Rust-native `rust.Result<T,E>`.
	**/
	public static inline function toRustResult<T, E>(value:reflaxe.std.Result<T, E>):rust.Result<T, E> {
		return cast value;
	}

	/**
		Converts Rust-native `rust.Result<T,E>` to portable `reflaxe.std.Result<T,E>`.
	**/
	public static inline function fromRustResult<T, E>(value:rust.Result<T, E>):reflaxe.std.Result<T, E> {
		return cast value;
	}
}
