package reflaxe.rust;

import reflaxe.rust.analyze.MetalViabilityAnalyzer.MetalViabilitySnapshot;
import reflaxe.rust.analyze.ProfileContractAnalyzer.ProfileContractDiagnostics;
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
	public var currentModuleLabel:Null<String>;

	// Metal fallback diagnostics (aggregated across transformed modules).
	var metalRawExprByModule:Map<String, Int>;
	var metalRawExprTotal:Int;
	var metalViabilitySnapshot:Null<MetalViabilitySnapshot>;
	var profileContractDiagnostics:ProfileContractDiagnostics;

	public var crateName(get, never):String;
	public var profile(get, never):RustProfile;

	public function new(build:RustBuildContext, usedModulePaths:Array<String>, inferredHxrtFeatures:Array<String>) {
		this.build = build;
		this.usedModulePaths = usedModulePaths;
		this.inferredHxrtFeatures = inferredHxrtFeatures;
		this.executedPasses = [];
		this.currentModuleLabel = null;
		this.metalRawExprByModule = [];
		this.metalRawExprTotal = 0;
		this.metalViabilitySnapshot = null;
		this.profileContractDiagnostics = {warnings: [], errors: []};
	}

	inline function get_crateName():String {
		return build.crateName;
	}

	inline function get_profile():RustProfile {
		return build.profile;
	}

	/**
		Records raw-expression (`ERaw`) fallback usage for a module.

		Why
		- `MetalRestrictionsPass` runs per transformed module; warning from each module creates
		  noisy, repetitive diagnostics.
		- We still need actionable data (which modules rely on fallback and how much).

		How
		- Passes call this once per module with the module label + local raw count.
		- `RustCompiler` emits one end-of-compile summary warning derived from this data.
	**/
	public function recordMetalRawExpr(moduleLabel:String, count:Int):Void {
		if (count <= 0)
			return;
		metalRawExprTotal += count;
		var key = moduleLabel;
		if (key == null || key.length == 0)
			key = "<unknown>";
		metalRawExprByModule.set(key, (metalRawExprByModule.exists(key) ? metalRawExprByModule.get(key) : 0) + count);
	}

	public inline function metalRawExprTotalCount():Int {
		return metalRawExprTotal;
	}

	public inline function metalRawExprModuleCount():Int {
		var n = 0;
		for (_ in metalRawExprByModule.keys())
			n++;
		return n;
	}

	/**
		Returns a deterministic snapshot of module-level raw-fallback counts.

		Why
		- Analyzer/report stages should consume stable data instead of internal mutable maps.
		- Deterministic ordering is required for reproducible CI artifacts.

		How
		- Converts `metalRawExprByModule` to an array sorted by module label.
	**/
	public function metalRawExprByModuleSnapshot():Array<{module:String, count:Int}> {
		var out:Array<{module:String, count:Int}> = [];
		for (module => count in metalRawExprByModule)
			out.push({module: module, count: count});
		out.sort((a, b) -> a.module < b.module ? -1 : (a.module > b.module ? 1 : 0));
		return out;
	}

	public function topMetalRawExprModules(limit:Int):Array<{module:String, count:Int}> {
		var out:Array<{module:String, count:Int}> = [];
		for (module => count in metalRawExprByModule)
			out.push({module: module, count: count});
		out.sort((a, b) -> {
			if (a.count != b.count)
				return a.count > b.count ? -1 : 1;
			return a.module < b.module ? -1 : (a.module > b.module ? 1 : 0);
		});
		return out.slice(0, limit < 0 ? 0 : limit);
	}

	/**
		Stores the latest metal viability analysis snapshot for this compile.

		Why
		- Milestone 22.1 computes viability data; milestone 22.2 consumes the same snapshot to emit
		  deterministic report artifacts.
	**/
	public function setMetalViability(snapshot:MetalViabilitySnapshot):Void {
		metalViabilitySnapshot = snapshot;
	}

	public function getMetalViability():Null<MetalViabilitySnapshot> {
		return metalViabilitySnapshot;
	}

	/**
		Stores latest profile-contract diagnostics for deterministic report emission.

		Why
		- Profile checks currently run before output emission and may produce warnings/errors.
		- Report writers should consume the exact analyzed snapshot, not recompute policy from scratch.

		How
		- `RustCompiler` runs `ProfileContractAnalyzer` once and stores diagnostics here.
		- Output-stage report emitters read this typed snapshot for `profile_contract.*`.
	**/
	public function setProfileContractDiagnostics(diagnostics:ProfileContractDiagnostics):Void {
		profileContractDiagnostics = diagnostics;
	}

	public function getProfileContractDiagnostics():ProfileContractDiagnostics {
		return profileContractDiagnostics;
	}
}
