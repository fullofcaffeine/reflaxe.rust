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
 * - `isRustFirst(profile)` identifies Rust-first profiles (`rusty`, `metal`).
 *
 * How
 * - Precedence:
 *   1) `-D reflaxe_rust_profile=<portable|idiomatic|rusty|metal>`
 *   2) aliases when profile define is absent: `-D rust_metal`, `-D rust_idiomatic`
 * - Conflicting combinations are rejected early with actionable compile errors.
 */
class ProfileResolver {
	public static function resolve():RustProfile {
		var profileDefine = Context.definedValue("reflaxe_rust_profile");
		var wantsIdiomaticAlias = Context.defined("rust_idiomatic");
		var wantsMetalAlias = Context.defined("rust_metal");

		if (profileDefine != null) {
			if (profileDefine.length == 0) {
				Context.error("`-D reflaxe_rust_profile` requires a value: portable|idiomatic|rusty|metal.", Context.currentPos());
			}

			var explicitProfile = parseProfile(profileDefine);
			if (wantsIdiomaticAlias && explicitProfile != Idiomatic) {
				Context.error("Conflicting defines: `-D rust_idiomatic` only matches `-D reflaxe_rust_profile=idiomatic`.", Context.currentPos());
			}
			if (wantsMetalAlias && explicitProfile != Metal) {
				Context.error("Conflicting defines: `-D rust_metal` only matches `-D reflaxe_rust_profile=metal`.", Context.currentPos());
			}
			return explicitProfile;
		}

		if (wantsIdiomaticAlias && wantsMetalAlias) {
			Context.error("Conflicting defines: choose only one of `-D rust_idiomatic` or `-D rust_metal`.", Context.currentPos());
		}

		if (wantsMetalAlias) {
			return Metal;
		}
		if (wantsIdiomaticAlias) {
			return Idiomatic;
		}
		return Portable;
	}

	public static inline function isRustFirst(profile:RustProfile):Bool {
		return profile == Rusty || profile == Metal;
	}

	static function parseProfile(profile:String):RustProfile {
		return switch (profile) {
			case "portable": Portable;
			case "idiomatic": Idiomatic;
			case "rusty": Rusty;
			case "metal": Metal;
			case _:
				Context.error("Unknown `-D reflaxe_rust_profile=" + profile + "`. Expected portable|idiomatic|rusty|metal.", Context.currentPos());
				Portable;
		}
	}
}
#end
