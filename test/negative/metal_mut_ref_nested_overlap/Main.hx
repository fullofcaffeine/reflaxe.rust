import rust.Borrow;
import rust.HashMap;
import rust.HashMapTools;

class Main {
	static function main():Void {
		var map = new HashMap<String, Int>();
		Borrow.withMut(map, first -> {
			HashMapTools.insert(first, "a", 1);
			Borrow.withMut(map, second -> {
				HashMapTools.insert(second, "b", 2);
			});
		});
	}
}
