package reflaxe.rust.passes;

import reflaxe.rust.CompilationContext;
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

	How
	- Leaves structured AST nodes untouched.
	- Applies string-level normalization only to literal raw chunks.
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
			case RRaw(s):
				RRaw(normalizeRaw(s));
			case _:
				item;
		}
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
