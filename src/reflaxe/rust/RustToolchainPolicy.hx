package reflaxe.rust;

/**
	Generated Rust toolchain compatibility constants.

	Why
	- Generated Cargo manifests must reject compilers older than the minimum version actually
	  exercised by CI.
	- Keeping this typed compiler consumer generated from rust-toolchain-policy.json prevents the
	  release runner, documentation, and emitted crate metadata from drifting independently.

	What
	- MINIMUM_SUPPORTED_RUST is the oldest rustc version in the supported consumer contract.
	- GENERATED_CARGO_RUST_VERSION is written to the Cargo rust-version field.

	How
	- Run npm run toolchain:sync after reviewing a policy change.
	- Never edit this file directly; npm run guard:rust-toolchain-policy verifies exact bytes.
**/
class RustToolchainPolicy {
	public static inline final MINIMUM_SUPPORTED_RUST:String = "1.96.0";
	public static inline final GENERATED_CARGO_RUST_VERSION:String = "1.96.0";
}
