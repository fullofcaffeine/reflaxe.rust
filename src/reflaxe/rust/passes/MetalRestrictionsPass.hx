package reflaxe.rust.passes;

import haxe.macro.Context;
import StringTools;
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
	  - hard-errors in strict metal mode or when a portable module is tagged with `@:haxeMetal`.
	  - optional debug trace (`-D rust_debug_metal_raw`) to print raw snippet origins while reducing
		fallback hotspots.

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
		var moduleLabel = context.currentModuleLabel != null ? context.currentModuleLabel : "<unknown>";
		var enforceForModule = context.profile == Metal || context.build.isMetalIslandModule(moduleLabel);
		if (!enforceForModule)
			return file;

		var rawExprCount = 0;
		RustPassTools.mapFile(file, s -> s, e -> {
			switch (e) {
				case ERaw(raw):
					rawExprCount++;
					#if eval
					if (Context.defined("rust_debug_metal_raw"))
						Context.warning("metal raw expr [" + moduleLabel + "] " + debugSnippet(raw), Context.currentPos());
					#end
				case _:
			}
			return e;
		});

		if (rawExprCount <= 0)
			return file;

		context.recordMetalRawExpr(moduleLabel, rawExprCount);
		#if eval
		var diagPos = context.modulePos(moduleLabel);
		if (diagPos == null)
			diagPos = Context.currentPos();
		#end

		if (context.profile == Metal && context.build.metalContractHardError) {
			#if eval
			Context.error("Metal contract violation in module `"
				+ moduleLabel
				+ "`: generated output still contains "
				+ rawExprCount
				+ " raw Rust expression node(s) (`ERaw`). "
				+ "This usually means a boundary still relies on string-injection fallback and is not metal-clean yet.",
				diagPos);
			#end
		}
		if (context.profile != Metal) {
			#if eval
			Context.error("Metal island violation in module `"
				+ moduleLabel
				+ "`: generated output still contains "
				+ rawExprCount
				+ " raw Rust expression node(s) (`ERaw`). "
				+ "Add typed lowering for this module before using `@:haxeMetal`.",
				diagPos);
			#end
		}
		return file;
	}

	static function debugSnippet(raw:String):String {
		if (raw == null)
			return "<null>";
		var out = StringTools.trim(raw);
		out = out.split("\r").join("\\r");
		out = out.split("\n").join("\\n");
		out = out.split("\t").join("\\t");
		if (out.length > 180)
			out = out.substr(0, 177) + "...";
		return out;
	}
}
