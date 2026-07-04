import rust.Borrow;
import rust.StrTools;
import rust.StringTools;

typedef BorrowSummary = {
	var hasHello:Bool;
	var nested:Array<Bool>;
}

class Main {
	static function main():Void {
		var haystack = "hello world";
		var summary:BorrowSummary = Borrow.withRef(haystack, borrowed -> ({
			hasHello: StrTools.with("hello", needle -> StringTools.contains(borrowed, needle)),
			nested: [StrTools.with("world", needle -> StringTools.contains(borrowed, needle))]
		}));

		trace(summary.hasHello);
	}
}
