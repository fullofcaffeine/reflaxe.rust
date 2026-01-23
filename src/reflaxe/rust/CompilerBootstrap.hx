package reflaxe.rust;

#if macro

import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;

/**
 * CompilerBootstrap
 *
 * WHAT
 * - Performs the earliest possible target-conditional classpath injection for reflaxe.rust.
 *
 * WHY
 * - Consumer installs rely on `extraParams.hxml` to invoke our bootstrap macros.
 * - Some compiler modules may reference types under this repo’s `std/` or vendored `reflaxe`.
 * - If we wait until `CompilerInit.Start()` to inject them, Haxe may type compiler modules
 *   before injection runs, leading to missing-type failures in fresh projects.
 *
 * HOW
 * - Invoked first from `extraParams.hxml`.
 * - If this compilation appears to be a Rust build (`-D rust_output` or custom target),
 *   compute the library root from this file’s resolved path and add:
 *   - `vendor/reflaxe/src` (vendored Reflaxe framework)
 *   - `std/` (target-specific overrides; currently minimal)
 */
class CompilerBootstrap {
	static var bootstrapped: Bool = false;

	public static function Start() {
		if (bootstrapped) return;
		bootstrapped = true;

		var targetName = Context.definedValue("target.name");
		var isRustBuild = (targetName == "rust" || Context.defined("rust_output"));

		try {
			var bootstrapPath = Context.resolvePath("reflaxe/rust/CompilerBootstrap.hx");
			var rustDir = Path.directory(bootstrapPath); // .../src/reflaxe/rust
			var reflaxeDir = Path.directory(rustDir);     // .../src/reflaxe
			var srcDir = Path.directory(reflaxeDir);      // .../src
			var libraryRoot = Path.directory(srcDir);     // .../

			var vendoredReflaxe = Path.normalize(Path.join([libraryRoot, "vendor", "reflaxe", "src"]));
			Compiler.addClassPath(vendoredReflaxe);

			if (!isRustBuild) return;

			var standardLibrary = Path.normalize(Path.join([libraryRoot, "std"]));
			Compiler.addClassPath(standardLibrary);
		} catch (e: haxe.Exception) {
			// If resolvePath fails in certain contexts, skip silently (non-rust targets)
		}
	}
}

#end

