package reflaxe.rust;

#if (macro || reflaxe_runtime)
import reflaxe.output.DataAndFileInfo;
import reflaxe.output.StringOrBytes;
import reflaxe.rust.ast.RustAST;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustASTTransformer;
import reflaxe.rust.ast.RustASTPrinter;

@:access(reflaxe.rust.RustCompiler)
class RustOutputIterator {
	var compiler:RustCompiler;
	var context:CompilationContext;
	var index:Int;
	var maxIndex:Int;

	public function new(compiler:RustCompiler) {
		this.compiler = compiler;
		this.context = compiler.createCompilationContext();
		this.compiler.currentCompilationContext = this.context;
		this.index = 0;
		this.maxIndex = compiler.classes.length + compiler.enums.length + compiler.typedefs.length + compiler.abstracts.length;
	}

	public function hasNext():Bool {
		return index < maxIndex;
	}

	public function next():DataAndFileInfo<StringOrBytes> {
		var astData:DataAndFileInfo<RustFile> = if (index < compiler.classes.length) {
			compiler.classes[index];
		} else if (index < compiler.classes.length + compiler.enums.length) {
			compiler.enums[index - compiler.classes.length];
		} else if (index < compiler.classes.length + compiler.enums.length + compiler.typedefs.length) {
			compiler.typedefs[index - compiler.classes.length - compiler.enums.length];
		} else {
			compiler.abstracts[
				index - compiler.classes.length - compiler.enums.length - compiler.typedefs.length
			];
		}
		index++;
		context.setCurrentModule(moduleLabel(astData), modulePos(astData));

		var transformed = RustASTTransformer.transform(astData.data, context);
		var printed = RustASTPrinter.printFile(transformed);
		return astData.withOutput(StringOrBytes.fromString(printed));
	}

	inline function moduleLabel(astData:DataAndFileInfo<RustFile>):String {
		var base = astData.baseType;
		if (base != null) {
			if (base.module != null && base.module.length > 0)
				return base.module;
			if (base.pack != null && base.pack.length > 0)
				return base.pack.concat([base.name]).join(".");
			return base.name;
		}
		if (astData.overrideFileName != null && astData.overrideFileName.length > 0)
			return astData.overrideFileName;
		return "<unknown>";
	}

	inline function modulePos(astData:DataAndFileInfo<RustFile>):Null<haxe.macro.Expr.Position> {
		return astData.baseType != null ? astData.baseType.pos : null;
	}
}
#end
