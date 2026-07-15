import reflaxe.rust.ast.RustAST.RustCompilerRawReason;
import reflaxe.rust.ast.RustAST.RustItem;
import reflaxe.rust.ast.RustAST.RustOrigin;
import reflaxe.rust.ast.RustAST.RustRawAuthority;
import reflaxe.rust.ast.RustAST.RustRawCode;
import reflaxe.rust.ast.RustASTPrinter;

class RustRawAuthorityContract {
	static function expect(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		var original = RustRawCode.compilerGenerated("fn generated() { }  ", RawStaticStorage);
		var normalized = original.withCode(StringTools.rtrim(original.code));

		expect(normalized.code == "fn generated() { }", "normalization must update only raw code bytes");
		expect(normalized.authorityId() == "compiler-owned", "compiler authority must remain queryable");
		expect(normalized.reasonId() == "static-storage", "compiler reason must remain stable");
		switch (normalized.authority) {
			case RawCompilerOwned(RawStaticStorage):
			case _: throw "normalization changed raw authority";
		}
		switch (normalized.origin) {
			case OriginCompilerGenerated:
			case OriginHaxeSource(_): throw "normalization changed compiler-generated origin";
		}
		expect(RustASTPrinter.printFile({items: [RRaw(normalized)]}) == "fn generated() { }\n", "typed metadata must not alter Rust output");
	}
}
