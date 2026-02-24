package reflaxe.rust;

#if (macro || reflaxe_runtime)
import haxe.io.Path;
import haxe.macro.Compiler;
import haxe.macro.Context;
import reflaxe.ReflectCompiler;
import reflaxe.preprocessors.ExpressionPreprocessor;
import reflaxe.preprocessors.ExpressionPreprocessor.*;
import reflaxe.rust.macros.AsyncSyntaxMacro;
import reflaxe.rust.macros.BoundaryEnforcer;
import reflaxe.rust.macros.StrictModeEnforcer;
import reflaxe.rust.ProfileResolver;
import reflaxe.rust.RustProfile;

/**
 * Initialization and registration of the Rust compiler.
 */
class CompilerInit {
	static var compilerRegistered:Bool = false;

	/**
	 * Initialize the Rust compiler.
	 * Use `--macro reflaxe.rust.CompilerInit.Start()` (via `extraParams.hxml`).
	 */
	public static function Start() {
		// For Haxe 4 builds, `target.name` may be unset; `-D rust_output=...` is the stable signal.
		var targetName = Context.definedValue("target.name");
		var isRustBuild = (targetName == "rust" || Context.defined("rust_output"));
		if (!isRustBuild)
			return;

		if (compilerRegistered)
			return;
		compilerRegistered = true;

		// Ensure Reflaxe hooks are initialized (vendored under vendor/reflaxe).
		ReflectCompiler.Start();

		// Target-conditional classpath gating for std overrides.
		// (Bootstrap adds std/ already; keep this as a belt-and-suspenders guard.)
		try {
			var compilerInitPath = Context.resolvePath("reflaxe/rust/CompilerInit.hx");
			var rustDir = Path.directory(compilerInitPath); // .../src/reflaxe/rust
			var reflaxeDir = Path.directory(rustDir); // .../src/reflaxe
			var srcDir = Path.directory(reflaxeDir); // .../src
			var libraryRoot = Path.directory(srcDir); // .../
			var standardLibrary = Path.normalize(Path.join([libraryRoot, "std"]));
			Compiler.addClassPath(standardLibrary);
		} catch (e:haxe.Exception) {}

		var profile = ProfileResolver.resolve();
		var wantsNoHxrt = Context.defined("rust_no_hxrt");
		if (wantsNoHxrt && profile != RustProfile.Metal) {
			Context.error("`-D rust_no_hxrt` currently requires `-D reflaxe_rust_profile=metal`.", Context.currentPos());
		}
		if (wantsNoHxrt) {
			var explicitHxrtFeatures = Context.definedValue("rust_hxrt_features");
			if (Context.defined("rust_hxrt_default_features")
				|| Context.defined("rust_hxrt_no_feature_infer")
				|| (explicitHxrtFeatures != null && explicitHxrtFeatures.length > 0)) {
				Context.error("`-D rust_no_hxrt` cannot be combined with hxrt feature defines (`rust_hxrt_default_features`, `rust_hxrt_no_feature_infer`, `rust_hxrt_features`).",
					Context.currentPos());
			}
		}

		// Repository policy: keep examples/snapshots "pure" (no __rust__ escape hatches).
		BoundaryEnforcer.init();

		// Metal policy: enable strict app-boundary mode by default so raw `__rust__` does not leak
		// into project sources. Framework-provided typed facades remain available.
		if (profile == RustProfile.Metal && !Context.defined("reflaxe_rust_strict")) {
			Compiler.define("reflaxe_rust_strict");
		}

		// Opt-in user policy (and metal default): forbid raw `__rust__` injection in project sources.
		StrictModeEnforcer.init();

		// Signal threaded sys support so upstream `sys.thread.*` APIs are available.
		// We provide target overrides for the core primitives under `std/sys/thread/*`.
		Compiler.define("target.threaded");

		// String representation policy:
		// - portable defaults to nullable HxString
		// - metal keeps legacy non-null String unless explicitly overridden
		var hasNullableStrings = Context.defined("rust_string_nullable");
		var hasNonNullableStrings = Context.defined("rust_string_non_nullable");
		if (hasNullableStrings && hasNonNullableStrings) {
			Context.error("Conflicting defines: choose only one of -D rust_string_nullable or -D rust_string_non_nullable.", Context.currentPos());
		}
		if (!hasNullableStrings && !hasNonNullableStrings) {
			if (!ProfileResolver.isRustFirst(profile)) {
				Compiler.define("rust_string_nullable");
			}
		}
		if (wantsNoHxrt && Context.defined("rust_string_nullable")) {
			Context.error("`-D rust_no_hxrt` is incompatible with `-D rust_string_nullable` because nullable strings rely on `hxrt::string::HxString`.",
				Context.currentPos());
		}

		if (Context.defined("rust_async_preview")) {
			Context.error("`-D rust_async_preview` was removed. Use `-D rust_async`.", Context.currentPos());
		}

		var wantsAsync = Context.defined("rust_async");
		if (wantsAsync) {
			if (!ProfileResolver.isRustFirst(profile)) {
				Context.error("Async (`-D rust_async`) currently requires `-D reflaxe_rust_profile=metal`.", Context.currentPos());
			}
			if (wantsNoHxrt) {
				Context.error("Async (`-D rust_async`) is incompatible with `-D rust_no_hxrt` because async lowering currently uses `hxrt::async_`.",
					Context.currentPos());
			}
			AsyncSyntaxMacro.init();
		}

		var prepasses:Array<ExpressionPreprocessor> = [];

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
