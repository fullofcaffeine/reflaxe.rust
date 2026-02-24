package reflaxe.rust.passes;

import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustFile;

/**
	RustPass

	Why
	- Profile-specific output behavior must be composable and testable.
	- A small pass interface lets us evolve codegen policy without growing monolithic lowering code.

	What
	- `name()`: stable pass identifier for diagnostics.
	- `run(file, context)`: pure AST transformation step.

	How
	- Passes are selected by `PassRunner` from the active profile.
	- Each pass receives the same `CompilationContext` snapshot.
**/
interface RustPass {
	public function name():String;
	public function run(file:RustFile, context:CompilationContext):RustFile;
}
