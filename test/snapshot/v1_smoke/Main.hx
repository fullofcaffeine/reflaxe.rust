enum E {
	A;
	B(i:Int);
}

class Counter {
	public var n:Int;

	public function new(n:Int) {
		this.n = n;
	}

	public function inc():Void {
		this.n = this.n + 1;
	}
}

class Main {
	static function main() {
		var xs = [3, 1, 2];
		xs.sort((a, b) -> a - b);
		Sys.println(xs.join(","));

		var removed = xs.splice(1, 1);
		Sys.println(removed.join(","));
		Sys.println(xs.join(","));

		var c = new Counter(0);
		c.inc();
		Sys.println(c.n);

		var e:E = B(7);
		var msg = switch (e) {
			case A: "A";
			case B(i): "B:" + i;
		}
		Sys.println(msg);

		var caught = try {
			throw "boom";
			"nope";
		} catch (e:String) {
			"caught";
		}
		Sys.println(caught);

		var f = (x:Int) -> x + 1;
		Sys.println(f(10));
	}
}
