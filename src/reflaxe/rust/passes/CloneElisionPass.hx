package reflaxe.rust.passes;

import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustExpr;
import reflaxe.rust.ast.RustAST.RustFile;

/**
	CloneElisionPass

	Why
	- Portable/metal profiles should avoid obviously redundant `.clone()` calls.
	- We need conservative elision rules that do not change ownership behavior.

	What
	- Removes `.clone()` when the receiver is an immediate literal expression:
	  - integer / float / bool / string literals.

	How
	- Rewrites `ECall(EField(<literal>, "clone"), [])` to the literal.
	- Does not touch path/local clones because those may be move-safety clones.
**/
class CloneElisionPass implements RustPass {
	public function new() {}

	public function name():String {
		return "clone_elision";
	}

	public function run(file:RustFile, _context:CompilationContext):RustFile {
		return RustPassTools.mapFile(file, s -> s, rewriteExpr);
	}

	function rewriteExpr(e:RustExpr):RustExpr {
		return switch (e) {
			case ECall(EField(target, "clone"), []):
				if (isLiteral(target)) target else e;
			case _:
				e;
		}
	}

	function isLiteral(e:RustExpr):Bool {
		return switch (e) {
			case ELitInt(_) | ELitFloat(_) | ELitBool(_) | ELitString(_):
				true;
			case _:
				false;
		}
	}
}
