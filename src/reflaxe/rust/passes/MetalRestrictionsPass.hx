package reflaxe.rust.passes;

import haxe.macro.Context;
import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;

/**
	MetalRestrictionsPass

	Why
	- Metal profile is intentionally strict: failures should be explicit and actionable.
	- Restriction checks should live in a dedicated pass stage so policy is testable.

	What
	- Enforces no-opinionated baseline contracts that are safe to apply immediately:
	  - keeps track of raw `ERaw` expression usage as a policy signal.
	  - emits an explicit warning in fallback mode, or hard-errors in strict metal mode.

	How
	- Walks the file and counts `ERaw(...)` expression nodes.
	- Emits an explicit fallback warning by default when raw nodes remain.
	- Escalates to compile error when the metal contract hard-error policy is enabled.
**/
class MetalRestrictionsPass implements RustPass {
	public function new() {}

	public function name():String {
		return "metal_restrictions";
	}

	public function run(file:RustFile, context:CompilationContext):RustFile {
		var rawExprCount = 0;
		RustPassTools.mapFile(file, s -> s, e -> {
			switch (e) {
				case ERaw(_):
					rawExprCount++;
				case _:
			}
			return e;
		});

		if (rawExprCount > 0 && context.build.metalContractHardError) {
			#if eval
			Context.error("Metal contract violation: generated output still contains raw Rust expression nodes (`ERaw`). "
				+ "This usually means a boundary still relies on string-injection fallback and is not metal-clean yet.",
				Context.currentPos());
			#end
		} else if (rawExprCount > 0) {
			#if eval
			Context.warning("Metal fallback active: generated output still contains "
				+ rawExprCount
				+ " raw Rust expression node(s) (`ERaw`). "
				+ "Add typed lowering for these boundaries or remove `-D rust_metal_allow_fallback` to enforce metal-clean output.",
				Context.currentPos());
			#end
		}
		return file;
	}
}
