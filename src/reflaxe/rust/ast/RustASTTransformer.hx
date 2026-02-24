package reflaxe.rust.ast;

import reflaxe.rust.ast.RustAST;
import reflaxe.rust.CompilationContext;
import reflaxe.rust.passes.PassRunner;

/**
	Rust AST transformer pass runner.

	Why
	- Generated AST shape should be refined by profile-specific, composable transforms instead of
	  embedding every output policy in expression lowering.

	What
	- Runs the selected pass pipeline (`PassRunner`) for the active profile.

	How
	- `CompilationContext.profile` determines the pass set.
	- Pass names are recorded in `CompilationContext.executedPasses` for diagnostics/tests.
**/
class RustASTTransformer {
	public static function transform(file:RustAST.RustFile, context:CompilationContext):RustAST.RustFile {
		return PassRunner.run(file, context);
	}
}
