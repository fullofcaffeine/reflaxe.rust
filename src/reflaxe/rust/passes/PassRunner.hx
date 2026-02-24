package reflaxe.rust.passes;

import reflaxe.rust.CompilationContext;
import reflaxe.rust.RustProfile;
import reflaxe.rust.ast.RustAST.RustFile;

/**
	PassRunner

	Why
	- Profile behavior must be explicit and versionable.
	- Centralizing pass selection avoids profile logic drift across compiler stages.

	What
	- Selects and runs the pass list for the active profile.
	- Records executed pass names in `CompilationContext`.

	How
	- `portable`: normalize + mut inference + clone elision (+ metal restrictions for `@:rustMetal` islands)
	- `metal`: portable set + borrow-scope stage + metal restrictions
	- `rust_no_hxrt`: appends a no-runtime verification stage (`NoHxrtPass`)
**/
class PassRunner {
	static final NORMALIZE:RustPass = new NormalizePass();
	static final MUT_INFERENCE:RustPass = new MutInferencePass();
	static final CLONE_ELISION:RustPass = new CloneElisionPass();
	static final BORROW_TIGHTEN:RustPass = new BorrowScopeTighteningPass();
	static final METAL_RESTRICTIONS:RustPass = new MetalRestrictionsPass();
	static final NO_HXRT:RustPass = new NoHxrtPass();

	public static function run(file:RustFile, context:CompilationContext):RustFile {
		var passes = selectPasses(context);
		var out = file;
		context.executedPasses = [];
		for (pass in passes) {
			out = pass.run(out, context);
			context.executedPasses.push(pass.name());
		}
		return out;
	}

	static function selectPasses(context:CompilationContext):Array<RustPass> {
		var passes = switch (context.profile) {
			case Portable:
				[NORMALIZE, MUT_INFERENCE, CLONE_ELISION];
			case Metal:
				[NORMALIZE, MUT_INFERENCE, CLONE_ELISION, BORROW_TIGHTEN, METAL_RESTRICTIONS];
		};
		if (context.build.noHxrt)
			passes.push(NO_HXRT);
		return passes;
	}
}
