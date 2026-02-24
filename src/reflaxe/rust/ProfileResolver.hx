package reflaxe.rust;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
 * Resolve and validate Rust profile defines.
 *
 * Why
 * - Profile selection is consumed by multiple compiler components (`CompilerInit`, `RustCompiler`,
 *   strict-boundary macros). Re-parsing defines in each place invites drift.
 * - We need deterministic precedence and explicit diagnostics when users combine incompatible defines.
 *
 * What
 * - `resolve()` returns a validated `RustProfile`.
 * - `isRustFirst(profile)` identifies Rust-first profiles (`metal`).
 *
 * How
 * - Precedence:
 *   1) `-D reflaxe_rust_profile=<portable|metal>`
 * - Legacy aliases are rejected so profile behavior stays explicit and non-ambiguous.
 */
class ProfileResolver {
	public static function resolve():RustProfile {
		var profileDefine = Context.definedValue("reflaxe_rust_profile");
		var wantsIdiomaticAlias = Context.defined("rust_idiomatic");
		var wantsMetalAlias = Context.defined("rust_metal");
		if (wantsIdiomaticAlias) {
			Context.error("`-D rust_idiomatic` is no longer supported. Use `-D reflaxe_rust_profile=portable`.", Context.currentPos());
		}
		if (wantsMetalAlias) {
			Context.error("`-D rust_metal` is no longer supported. Use `-D reflaxe_rust_profile=metal`.", Context.currentPos());
		}

		if (profileDefine != null) {
			if (profileDefine.length == 0) {
				Context.error("`-D reflaxe_rust_profile` requires a value: portable|metal.", Context.currentPos());
			}
			return parseProfile(profileDefine);
		}
		return Portable;
	}

	public static inline function isRustFirst(profile:RustProfile):Bool {
		return profile == Metal;
	}

	static function parseProfile(profile:String):RustProfile {
		return switch (profile) {
			case "portable": Portable;
			case "metal": Metal;
			case _:
				Context.error("Unknown `-D reflaxe_rust_profile=" + profile + "`. Expected portable|metal.", Context.currentPos());
				Portable;
		}
	}
}
#end
