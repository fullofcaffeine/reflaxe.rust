package reflaxe.rust;

/**
 * CompilationContext
 *
 * Holds cross-pass state/config for compilation.
 *
 * POC: minimal. Expand as transformer passes and Cargo metadata grow.
 */
class CompilationContext {
	public var crateName: String;

	public function new(crateName: String) {
		this.crateName = crateName;
	}
}

