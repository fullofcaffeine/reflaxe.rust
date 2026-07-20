import rust.Borrow;
import rust.MutSliceTools;
import rust.SliceTools;
import rust.StrTools;
import rust.StringTools;
import rust.Vec;

private enum BorrowBranch {
	First;
	Second;
}

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

	static function observeScore(_value:Int):Void {}

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
				var chooseFirst = score == 0;
				score += consumeMutRef((cast (chooseFirst ? maybe : maybe) : Null<rust.MutRef<Vec<Int>>>));
				score += consumeMutRef(maybe);
				score += consumeMutRef((cast switch (score) {
					case 4: maybe;
					default: maybe;
				} : Null<rust.MutRef<Vec<Int>>>));
				score += consumeMutRef(maybe);
				var branch = score == 6 ? BorrowBranch.First : BorrowBranch.Second;
				score += consumeMutRef((cast switch (branch) {
					case First: {
						observeScore(score);
						maybe;
					}
					case Second: {
						observeScore(score);
						maybe;
					}
				} : Null<rust.MutRef<Vec<Int>>>));
				score += consumeMutRef(maybe);
				score += consumeMutRef((cast {
					observeScore(score);
					maybe;
				} : Null<rust.MutRef<Vec<Int>>>));
				score += consumeMutRef(maybe);
				score += consumeMutRef(chooseFirst ? maybe : maybe);
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
				var chooseFirst = score == 0;
				score += consumeMutSlice((cast (chooseFirst ? maybe : maybe) : Null<rust.MutSlice<Int>>));
				score += consumeMutSlice(maybe);
				score += consumeMutSlice((cast switch (score) {
					case 16: maybe;
					default: maybe;
				} : Null<rust.MutSlice<Int>>));
				score += consumeMutSlice(maybe);
				var branch = score == 24 ? BorrowBranch.First : BorrowBranch.Second;
				score += consumeMutSlice((cast switch (branch) {
					case First: {
						observeScore(score);
						maybe;
					}
					case Second: {
						observeScore(score);
						maybe;
					}
				} : Null<rust.MutSlice<Int>>));
				score += consumeMutSlice(maybe);
				score += consumeMutSlice((cast {
					observeScore(score);
					maybe;
				} : Null<rust.MutSlice<Int>>));
				score += consumeMutSlice(maybe);
				score += consumeMutSlice(chooseFirst ? maybe : maybe);
			}
			score;
		});

		trace(ok && mutableRefScore == 18 && sliceScore == 4 && mutableSliceScore == 72);
	}
}
