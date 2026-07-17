import rust.Borrow;
import rust.StrTools;
import rust.StringTools;

class Main {
	static function main():Void {
		var s = "hello world";
		var ok = Borrow.withRef(s, haystack -> {
			var maybeHaystack:Null<rust.Ref<String>> = haystack;
			var stillBorrowed = maybeHaystack != null;
			StrTools.with("world", needle -> StringTools.contains(haystack, needle) && stillBorrowed);
		});

		trace(ok);
	}
}
