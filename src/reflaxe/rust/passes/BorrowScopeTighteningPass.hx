package reflaxe.rust.passes;

import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustFile;

/**
	BorrowScopeTighteningPass

	Why
	- Rust-first profiles should keep mutable/read borrows short where possible.
	- Borrow-scope work belongs in a dedicated pass pipeline stage, not ad-hoc expression codegen.

	What
	- Current implementation is a conservative no-op marker pass.

	How
	- Kept explicit in the pipeline so future borrow-scope rewrites can land without changing
	  profile wiring or pass contracts.
**/
class BorrowScopeTighteningPass implements RustPass {
	public function new() {}

	public function name():String {
		return "borrow_scope_tightening";
	}

	public function run(file:RustFile, _context:CompilationContext):RustFile {
		return file;
	}
}
