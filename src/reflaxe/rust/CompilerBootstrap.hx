package reflaxe.rust;

#if macro
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;
import sys.FileSystem;

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
 *   - `std/` when present (local repository fallback/classification path)
 *
 * Packaging note
 * - Release zips flatten `stdPaths` into `classPath` (`src/**`) to mirror Reflaxe build behavior.
 * - Dev checkouts mirror those top-level `std/**` entries under `src/**` with tracked symlinks so
 *   upstream-colliding modules are visible before this macro runs.
 * - In the packaged layout there is no top-level `std/`, so we only add it when the directory exists.
 */
class CompilerBootstrap {
	static var bootstrapped:Bool = false;

	public static function Start() {
		if (bootstrapped)
			return;
		bootstrapped = true;

		var targetName = Context.definedValue("target.name");
		var isRustBuild = (targetName == "rust" || Context.defined("rust_output"));

		try {
			var bootstrapPath = Context.resolvePath("reflaxe/rust/CompilerBootstrap.hx");
			var rustDir = Path.directory(bootstrapPath); // .../src/reflaxe/rust
			var reflaxeDir = Path.directory(rustDir); // .../src/reflaxe
			var srcDir = Path.directory(reflaxeDir); // .../src
			var libraryRoot = Path.directory(srcDir); // .../

			var vendoredReflaxe = Path.normalize(Path.join([libraryRoot, "vendor", "reflaxe", "src"]));
			if (FileSystem.exists(vendoredReflaxe) && FileSystem.isDirectory(vendoredReflaxe))
				Compiler.addClassPath(vendoredReflaxe);

			if (!isRustBuild)
				return;

			var standardLibrary = Path.normalize(Path.join([libraryRoot, "std"]));
			if (FileSystem.exists(standardLibrary) && FileSystem.isDirectory(standardLibrary))
				Compiler.addClassPath(standardLibrary);
		} catch (e:Dynamic) {
			// If resolvePath fails in certain contexts, skip silently (non-rust targets)
		}
	}
}
#end
