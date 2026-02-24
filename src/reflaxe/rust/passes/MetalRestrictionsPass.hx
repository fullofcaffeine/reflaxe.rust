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
	  - hard-errors in strict metal mode.

	How
	- Walks the file and counts `ERaw(...)` expression nodes.
	- Records per-module counts into `CompilationContext` for an end-of-compile summary.
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

		if (rawExprCount <= 0)
			return file;

		var moduleLabel = context.currentModuleLabel != null ? context.currentModuleLabel : "<unknown>";
		context.recordMetalRawExpr(moduleLabel, rawExprCount);

		if (context.build.metalContractHardError) {
			#if eval
			Context.error("Metal contract violation in module `"
				+ moduleLabel
				+ "`: generated output still contains "
				+ rawExprCount
				+ " raw Rust expression node(s) (`ERaw`). "
				+ "This usually means a boundary still relies on string-injection fallback and is not metal-clean yet.",
				Context.currentPos());
			#end
		}
		return file;
	}
}
