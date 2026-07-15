package reflaxe.rust.passes;

import reflaxe.rust.RustDiagnostic;
import reflaxe.rust.RustDiagnostic.RustDiagnosticId;
import haxe.macro.Context;
import StringTools;
import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustOrigin;

/**
	MetalRestrictionsPass

	Why
	- Metal profile is intentionally strict: failures should be explicit and actionable.
	- Restriction checks should live in a dedicated pass stage so policy is testable.

	What
	- Enforces no-opinionated baseline contracts that are safe to apply immediately:
	  - keeps track of raw `ERaw` expression usage as a policy signal.
	  - hard-errors in strict metal mode or when a portable module is tagged with `@:rustMetal`.
	  - optional debug trace (`-D rust_debug_metal_raw`) to print raw snippet origins while reducing
		fallback hotspots.

	How
	- Walks the file and counts `ERaw(...)` expression nodes.
	- Anchors raw debug warnings at `OriginHaxeSource`; compiler-generated fragments fall back to the
	  owning module position because they have no honest source span.
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
		#if eval
		var diagPos = context.diagnosticPos(moduleLabel);
		if (diagPos == null)
			diagPos = Context.currentPos();
		#end

		var rawExprCount = 0;
		RustPassTools.mapFile(file, s -> s, e -> {
				switch (e) {
				case ERaw(raw):
					rawExprCount++;
					#if eval
					if (Context.defined("rust_debug_metal_raw")) {
						var warningPos = switch (raw.origin) {
							case OriginHaxeSource(pos): pos;
							case OriginCompilerGenerated: diagPos;
						};
						Context.warning("metal raw expr [" + moduleLabel + "] [" + raw.authorityId() + ":" + raw.reasonId() + "] "
							+ debugSnippet(raw.code), warningPos);
					}
					#end
				case _:
			}
			return e;
		});

		if (rawExprCount <= 0)
			return file;

		context.recordMetalRawExpr(moduleLabel, rawExprCount);

		if (context.profile == Metal && context.build.metalContractHardError) {
			#if eval
			RustDiagnostic.error(RustDiagnosticId.ProfileContractError, "Metal contract violation in module `"
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
			RustDiagnostic.error(RustDiagnosticId.ProfileContractError, "Metal island violation in module `"
				+ moduleLabel
				+ "`: generated output still contains "
				+ rawExprCount
				+ " raw Rust expression node(s) (`ERaw`). "
				+ "Add typed lowering for this module before using `@:rustMetal`.",
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
