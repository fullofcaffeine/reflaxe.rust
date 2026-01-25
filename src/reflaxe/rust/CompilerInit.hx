package reflaxe.rust;

#if (macro || reflaxe_runtime)

import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;
import reflaxe.ReflectCompiler;
import reflaxe.preprocessors.ExpressionPreprocessor;
import reflaxe.preprocessors.ExpressionPreprocessor.*;
import reflaxe.rust.macros.BoundaryEnforcer;
import reflaxe.rust.macros.StrictModeEnforcer;

/**
 * Initialization and registration of the Rust compiler.
 */
class CompilerInit {
	static var compilerRegistered: Bool = false;

	/**
	 * Initialize the Rust compiler.
	 * Use `--macro reflaxe.rust.CompilerInit.Start()` (via `extraParams.hxml`).
	 */
	public static function Start() {
		// For Haxe 4 builds, `target.name` may be unset; `-D rust_output=...` is the stable signal.
		var targetName = Context.definedValue("target.name");
		var isRustBuild = (targetName == "rust" || Context.defined("rust_output"));
		if (!isRustBuild) return;

		if (compilerRegistered) return;
		compilerRegistered = true;

		// Ensure Reflaxe hooks are initialized (vendored under vendor/reflaxe).
		ReflectCompiler.Start();

		// Target-conditional classpath gating for std overrides.
		// (Bootstrap adds std/ already; keep this as a belt-and-suspenders guard.)
		try {
			var compilerInitPath = Context.resolvePath("reflaxe/rust/CompilerInit.hx");
			var rustDir = Path.directory(compilerInitPath); // .../src/reflaxe/rust
			var reflaxeDir = Path.directory(rustDir);       // .../src/reflaxe
			var srcDir = Path.directory(reflaxeDir);        // .../src
			var libraryRoot = Path.directory(srcDir);       // .../
			var standardLibrary = Path.normalize(Path.join([libraryRoot, "std"]));
			Compiler.addClassPath(standardLibrary);
		} catch (e: haxe.Exception) {}

		// Repository policy: keep examples/snapshots "pure" (no __rust__ escape hatches).
		BoundaryEnforcer.init();

		// Opt-in user policy: forbid __rust__ injection in project sources.
		StrictModeEnforcer.init();

		var prepasses: Array<ExpressionPreprocessor> = [];

		ReflectCompiler.AddCompiler(new RustCompiler(), {
			fileOutputExtension: ".rs",
			outputDirDefineName: "rust_output",
			fileOutputType: FilePerModule,
			targetCodeInjectionName: "__rust__",
			ignoreBodilessFunctions: false,
			ignoreExterns: true,
			trackUsedTypes: true,
			expressionPreprocessors: prepasses
		});
	}
}

#end
