#if macro
import haxe.macro.Context;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustOrigin;
import reflaxe.rust.ast.RustAST.RustRawCode;
import reflaxe.rust.ast.RustASTPrinter;

/**
	Executable contract for the two remaining raw-authority boundaries.

	Why / What / How
	- Compiler-owned Rust text is no longer constructible, so the contract exercises metadata and
	  explicit source authority instead of preserving a migration-debt factory for test convenience.
	- Normalization may change only printable bytes; the exact authority, reason, and Haxe position
	  must survive unchanged.
	- The Node harness separately proves direct construction is private and that the generated
	  call-site inventory fails on unreviewed growth.
**/
class RustRawAuthorityContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	public static function run():Void {
		var pos = Context.currentPos();
		var original = RustRawCode.traitImplementationAt("fn generated() { }  ", pos);
		var normalized = original.withCode(StringTools.rtrim(original.code));

		expect(normalized.code == "fn generated() { }", "normalization must update only raw code bytes");
		expect(normalized.authorityId() == "metadata-owned", "metadata authority must remain queryable");
		expect(normalized.reasonId() == "trait-implementation", "metadata reason must remain stable");
		switch (normalized.origin) {
			case OriginHaxeSource(actual):
				expect(Context.getPosInfos(actual).min == Context.getPosInfos(pos).min,
					"normalization changed the raw fragment source position");
			case OriginCompilerGenerated(_): throw "author-supplied metadata became compiler-generated";
		}
		expect(RustASTPrinter.printFile({items: [RRaw(normalized)]}) == "fn generated() { }\n",
			"typed metadata must not alter Rust output");

		var source = RustRawCode.targetCodeInjectionAt("value", pos);
		expect(source.authorityId() == "source-owned" && source.reasonId() == "target-code-injection",
			"source injection lost its exact authority classification");
	}
}
#end
