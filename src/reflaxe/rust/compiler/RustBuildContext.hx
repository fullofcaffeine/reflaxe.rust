package reflaxe.rust.compiler;

import reflaxe.rust.RustProfile;

/**
	RustBuildContext

	Why
	- `RustCompiler` currently carries most compile-time knobs as local fields.
	- AST passes and output stages need a stable, typed view of those knobs without reaching into
	  the compiler internals directly.

	What
	- Immutable build-level metadata for a single compile:
	  - crate identity (`crateName`)
	  - selected profile (`profile`)
	  - profile/boundary toggles used by passes (`asyncEnabled`, `nullableStrings`, strict flags)
	  - optional metal-island module set (`metalIslandModules`) for strict checks in portable mode

	How
	- Constructed once in `RustCompiler.createCompilationContext()`.
	- Stored inside `CompilationContext` and consumed by pass runner / diagnostics.
**/
class RustBuildContext {
	public final crateName:String;
	public final profile:RustProfile;
	public final asyncEnabled:Bool;
	public final nullableStrings:Bool;
	public final strictExamples:Bool;
	public final strictUserBoundaries:Bool;
	public final metalContractHardError:Bool;
	public final noHxrt:Bool;
	public final metalIslandModules:Array<String>;

	public function new(crateName:String, profile:RustProfile, asyncEnabled:Bool, nullableStrings:Bool, strictExamples:Bool, strictUserBoundaries:Bool,
			metalContractHardError:Bool, noHxrt:Bool, metalIslandModules:Array<String>) {
		this.crateName = crateName;
		this.profile = profile;
		this.asyncEnabled = asyncEnabled;
		this.nullableStrings = nullableStrings;
		this.strictExamples = strictExamples;
		this.strictUserBoundaries = strictUserBoundaries;
		this.metalContractHardError = metalContractHardError;
		this.noHxrt = noHxrt;
		this.metalIslandModules = metalIslandModules == null ? [] : metalIslandModules.copy();
		this.metalIslandModules.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
	}

	public inline function hasMetalIslands():Bool {
		return metalIslandModules.length > 0;
	}

	public inline function isMetalIslandModule(moduleLabel:String):Bool {
		return moduleLabel != null && metalIslandModules.indexOf(moduleLabel) != -1;
	}
}
