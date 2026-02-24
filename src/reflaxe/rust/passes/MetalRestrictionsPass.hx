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
	  - optionally hard-errors when `-D rust_metal_contract_hard_error` is enabled.

	How
	- Walks the file and counts `ERaw(...)` expression nodes.
	- Records a warning by default; escalates to compile error when the hard-error define is set.
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
		}
		return file;
	}
}
