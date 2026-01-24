import rust.Borrow;
import rust.HashMap;
import rust.HashMapTools;
import rust.OptionTools;

using rust.OptionTools;

class Main {
	static function main(): Void {
		var m = new HashMap<String, Int>();

		Borrow.withMut(m, mm -> {
			HashMapTools.insert(mm, "a", 1);
			HashMapTools.insert(mm, "b", 2);
		});

		trace(HashMapTools.len(m));

		var keyA = "a";
		Borrow.withRef(keyA, kA -> {
			Borrow.withMut(m, mm -> {
				var removed = HashMapTools.remove(mm, kA);
				trace(removed.isSome());
			});
		});

		trace(HashMapTools.len(m));
	}
}

