using Lambda;

class Main {
	static function countIf(it:Array<Int>, ?pred:Null<(x:Int) -> Bool>):Int {
		var n = 0;
		if (pred == null) {
			for (_ in it) n++;
		} else {
			for (x in it) if (pred(x)) n++;
		}
		return n;
	}

	static function retNull(ok:Bool):Null<Int> {
		if (ok) return 1;
		return null;
	}

	static function tailNull(ok:Bool):Null<Int> {
		return if (ok) 2 else null;
	}

	static function main() {
		var a = [1, 2, 3, 4];

		// Optional arg omitted (should become None).
		var t0 = countIf(a);

		// Optional arg provided (should become Some(Rc<dyn Fn...>)).
		var t1 = countIf(a, x -> x == 2 || x == 4);

		// Inline std helper also uses an optional predicate.
		var t2 = a.count();
		var t3 = a.count(x -> x > 2);

		var x:Null<Int> = null;
		x = 3;

		var r0 = retNull(true);
		var r1 = retNull(false);
		var r2 = tailNull(true);
		var r3 = tailNull(false);

		Sys.println(t0);
		Sys.println(t1);
		Sys.println(t2);
		Sys.println(t3);
		Sys.println(x == null);
		Sys.println(x != null);
		Sys.println(r0 == null);
		Sys.println(r1 == null);
		Sys.println(r2 == null);
		Sys.println(r3 == null);
	}
}
