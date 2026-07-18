import rust.Borrow;
import rust.MutSliceTools;
import rust.SliceTools;
import rust.StrTools;
import rust.StringTools;
import rust.Vec;

class Main {
	static function consumeRef(_value:rust.Ref<String>):Int {
		return 1;
	}

	static function consumeMutRef(_value:rust.MutRef<Vec<Int>>):Int {
		return 2;
	}

	static function consumeSlice(_value:rust.Slice<Int>):Int {
		return 4;
	}

	static function consumeMutSlice(_value:rust.MutSlice<Int>):Int {
		return 8;
	}

	static function main():Void {
		var s = "hello world";
		var ok = Borrow.withRef(s, haystack -> {
			var maybeHaystack:Null<rust.Ref<String>> = haystack;
			var stillBorrowed = maybeHaystack != null;
			var consumed = maybeHaystack != null ? consumeRef(maybeHaystack) : 0;
			StrTools.with("world", needle -> StringTools.contains(haystack, needle) && stillBorrowed && consumed == 1);
		});

		var values = new Vec<Int>();
		values.push(1);
		values.push(2);

		var mutableRefScore = Borrow.withMut(values, borrowed -> {
			var maybe:Null<rust.MutRef<Vec<Int>>> = borrowed;
			var score = 0;
			if (maybe != null) {
				score += consumeMutRef(maybe);
				score += consumeMutRef(maybe);
				score += consumeMutRef({
					maybe;
				});
			}
			score;
		});

		var sliceScore = SliceTools.with(values, borrowed -> {
			var maybe:Null<rust.Slice<Int>> = borrowed;
			maybe != null ? consumeSlice(maybe) : 0;
		});

		var mutableSliceScore = MutSliceTools.with(values, borrowed -> {
			var maybe:Null<rust.MutSlice<Int>> = borrowed;
			var score = 0;
			if (maybe != null) {
				score += consumeMutSlice(maybe);
				score += consumeMutSlice(maybe);
				score += consumeMutSlice({
					maybe;
				});
			}
			score;
		});

		trace(ok && mutableRefScore == 6 && sliceScore == 4 && mutableSliceScore == 24);
	}
}
