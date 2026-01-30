import rust.VecTools;

class Main {
	static function main() {
		var a = [1, 2];

		// Array -> Vec is an explicit, deep conversion (clones elements).
		var v = VecTools.fromArray(a);
		v.push(3);

		// Vec -> Array is an explicit conversion (moves the Vec into an Array handle).
		var a2 = VecTools.toArray(v);

		Sys.println(a.length); // 2
		Sys.println(a2.length); // 3

		// Array aliasing remains intact (Haxe semantics).
		var b = a;
		b.push(4);
		Sys.println(a.length); // 3
		Sys.println(b.length); // 3
		Sys.println(a2.length); // 3 (independent)
	}
}

