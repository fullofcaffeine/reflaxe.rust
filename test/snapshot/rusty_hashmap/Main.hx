import rust.Borrow;
import rust.HashMap;
import rust.HashMapTools;
import rust.Option;

class Main {
	static function main(): Void {
		var m = new HashMap<String, Int>();
		m.insert("a", 1);
		m.insert("b", 2);

		var key = "b";
		Borrow.withRef(key, k -> {
			var v = m.get(k);
			switch (v) {
				case Some(x):
					trace(x);
				case None:
					trace(-1);
			}
		});

		var keyCount = 0;
		for (_ in m.keys()) {
			keyCount = keyCount + 1;
		}
		trace(keyCount);

		trace(HashMapTools.len(m));
	}
}
