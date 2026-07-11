/**
 * Why: Structured Cargo metadata and metadata-owned Rust sources are generated-crate contracts.
 * What: Declares one dependency in two compatible pieces and owns both file and directory sources.
 * How: The snapshot proves deterministic feature union, dependency rendering, source copying, and
 * root module inclusion without relying on application-side raw Rust injection.
 */
@:rustCargo({name: "serde", version: "1", features: ["derive"]})
@:rustCargo({name: "serde", version: "1", features: ["alloc"], defaultFeatures: false})
@:rustExtraSrc("native/artifact_helper.rs")
@:rustExtraSrcDir("native_dir")
class Main {
	static function main():Void {
		trace("generated artifact contract");
	}
}
