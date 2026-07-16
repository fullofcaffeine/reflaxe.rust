package reflaxe.rust.passes;

import reflaxe.rust.CompilationContext;
import reflaxe.rust.ast.RustAST.RustAssociatedItem;
import reflaxe.rust.ast.RustAST.RustFile;
import reflaxe.rust.ast.RustAST.RustItem;

/**
	NormalizePass

	Why
	- Deterministic output is easier to snapshot-review and diff.
	- Raw-item emitters can accidentally produce trailing whitespace/noise.

	What
	- Trims trailing whitespace in `RRaw` items.
	- Collapses repeated blank lines in `RRaw` blocks.
	- Applies the same normalization to the metadata-owned raw body inside a structural trait impl.

	How
	- Recurses through attributed items, inline modules, traits, and impls without changing typed syntax.
	- Applies string-level normalization only to classified raw chunks, including `AssocRaw`.
**/
class NormalizePass implements RustPass {
	public function new() {}

	public function name():String {
		return "normalize";
	}

	public function run(file:RustFile, _context:CompilationContext):RustFile {
		return {
			items: [for (item in file.items) normalizeItem(item)]
		};
	}

	function normalizeItem(item:RustItem):RustItem {
		return switch (item) {
			case RAttributed(value):
				RAttributed(value.withTarget(normalizeItem(value.target)));
			case RModule(declaration):
				if (!declaration.isInline)
					item;
				else
					RModule(declaration.withItems([for (child in declaration) normalizeItem(child)]));
			case RTrait(declaration):
				RTrait(declaration.withItems([for (associated in declaration) normalizeAssociatedItem(associated)]));
			case RImpl(declaration):
				RImpl(declaration.withItems([for (associated in declaration) normalizeAssociatedItem(associated)]));
			case RRaw(fragment):
				RRaw(fragment.withCode(normalizeRaw(fragment.code)));
			case _:
				item;
		}
	}

	function normalizeAssociatedItem(item:RustAssociatedItem):RustAssociatedItem {
		return switch (item) {
			case AssocRaw(fragment): AssocRaw(fragment.withCode(normalizeRaw(fragment.code)));
			case AssocFunction(_) | AssocType(_) | AssocConst(_): item;
		};
	}

	function normalizeRaw(s:String):String {
		var lines = s.split("\n");
		var out:Array<String> = [];
		var blankCount = 0;
		for (line in lines) {
			var trimmedRight = StringTools.rtrim(line);
			var isBlank = StringTools.trim(trimmedRight).length == 0;
			if (isBlank) {
				blankCount++;
				if (blankCount > 1)
					continue;
			} else {
				blankCount = 0;
			}
			out.push(trimmedRight);
		}
		return out.join("\n");
	}
}
