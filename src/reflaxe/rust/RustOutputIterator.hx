package reflaxe.rust;

#if (macro || reflaxe_runtime)
import reflaxe.output.DataAndFileInfo;
import reflaxe.output.OutputPath;
import reflaxe.output.StringOrBytes;
import reflaxe.rust.RustSourceMap;
import reflaxe.rust.ast.RustAST;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustASTTransformer;
import reflaxe.rust.ast.RustASTPrinter;

using reflaxe.helpers.BaseTypeHelper;

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
		var printed = RustASTPrinter.printFileWithSourceMap(transformed, generatedFile(astData));
		context.recordSourceMapFile(printed);
		if (index == maxIndex) {
			compiler.setExtraFile(OutputPath.fromStr("rust-source-map.json"),
				RustSourceMap.encode(context.sourceMapFileSnapshot(), Sys.getCwd()));
		}
		return astData.withOutput(StringOrBytes.fromString(printed.code));
	}

	/**
		Reconstructs the exact relative filename owned by Reflaxe's file-per-module writer.

		Why / What / How
		- `DataAndFileInfo` exposes the typed filename inputs, but `OutputManager.overrideFileName` is
		  private and offers no public path query. Source maps still need the name before the manager writes
		  the returned chunk.
		- This narrow adapter mirrors the framework's `overrideDirectory + overrideFileName/moduleId`
		  rule and reads the compiler's configured extension instead of duplicating `.rs` as policy.
		- A missing base type fails here because Reflaxe's file-per-module writer also requires it.
	**/
	function generatedFile(astData:DataAndFileInfo<RustFile>):String {
		if (astData.baseType == null)
			throw "Rust file-per-module source mapping requires Reflaxe base-type metadata";
		var name = astData.overrideFileName != null ? astData.overrideFileName : astData.baseType.moduleId();
		var relative = (astData.overrideDirectory != null ? astData.overrideDirectory + "/" : "") + name;
		return RustSourceMap.requireRelativePath(relative + compiler.options.fileOutputExtension, "generated Rust file");
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
