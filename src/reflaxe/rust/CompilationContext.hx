package reflaxe.rust;

import reflaxe.rust.compiler.RustBuildContext;

/**
 * CompilationContext
 *
 * Holds cross-pass state/config for a single compiler run.
 *
 * Why
 * - AST passes need a stable snapshot of build settings (profile, boundary strictness, crate name).
 * - Output stages (Cargo generation/runtime emission) need shared data (used module set, inferred
 *   runtime features) without reaching into monolithic compiler internals.
 *
 * What
 * - `build`: immutable build-level settings.
 * - `usedModulePaths`: module/type-usage summary captured during lowering.
 * - `inferredHxrtFeatures`: final runtime feature set selected by compiler logic.
 * - `executedPasses`: ordered pass names applied in `RustASTTransformer`.
 *
 * How
 * - Constructed once from `RustCompiler.createCompilationContext()`.
 * - Passed to every AST transform pass and available to output stages.
 */
class CompilationContext {
	public final build:RustBuildContext;
	public final usedModulePaths:Array<String>;
	public final inferredHxrtFeatures:Array<String>;
	public var executedPasses:Array<String>;

	public var crateName(get, never):String;
	public var profile(get, never):RustProfile;

	public function new(build:RustBuildContext, usedModulePaths:Array<String>, inferredHxrtFeatures:Array<String>) {
		this.build = build;
		this.usedModulePaths = usedModulePaths;
		this.inferredHxrtFeatures = inferredHxrtFeatures;
		this.executedPasses = [];
	}

	inline function get_crateName():String {
		return build.crateName;
	}

	inline function get_profile():RustProfile {
		return build.profile;
	}
}
