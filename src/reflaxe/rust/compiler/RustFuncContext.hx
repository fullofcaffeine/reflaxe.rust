package reflaxe.rust.compiler;

/**
	RustFuncContext

	Why
	- Function lowering maintains many related maps (mutated locals, argument aliases, local names).
	- Keeping these values inside a typed context object makes the invariants explicit and simplifies
	  future extraction into dedicated lower/analyze modules.

	What
	- Function identity (`functionName`) + async/return contract.
	- Typed references to mutation/read tracking maps used during lowering.

	How
	- Instantiated in `withFunctionContext(...)`.
	- The compiler still owns the legacy fields, but this object is now the canonical grouped view
	  used by new passes/analyzers.
**/
class RustFuncContext {
	public final functionName:String;
	public final isAsync:Bool;
	public final expectedReturnTypeName:String;
	public final mutatedArgs:Array<String>;
	public final localNamesCount:Int;
	public final localReadCountEntries:Int;

	public function new(functionName:String, isAsync:Bool, expectedReturnTypeName:String, mutatedArgs:Array<String>, localNamesCount:Int,
			localReadCountEntries:Int) {
		this.functionName = functionName;
		this.isAsync = isAsync;
		this.expectedReturnTypeName = expectedReturnTypeName;
		this.mutatedArgs = mutatedArgs;
		this.localNamesCount = localNamesCount;
		this.localReadCountEntries = localReadCountEntries;
	}
}
