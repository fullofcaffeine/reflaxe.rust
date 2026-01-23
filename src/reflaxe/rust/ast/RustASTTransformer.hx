package reflaxe.rust.ast;

import reflaxe.rust.ast.RustAST;
import reflaxe.rust.CompilationContext;

/**
 * Rust AST transformer pass runner.
 *
 * POC: identity transform. Add passes here (mutability inference, borrow scope shrink, etc.)
 * as the target grows.
 */
class RustASTTransformer {
	public static function transform(file: RustAST.RustFile, _context: CompilationContext): RustAST.RustFile {
		return file;
	}
}
