class Counter {
	public var n:Int;

	public function new(n:Int) {
		this.n = n;
	}

	public function add(x:Int):Int {
		n += x;
		return n;
	}

	public function inc():Void {
		n++;
	}

	public function bindAdd():Int->Int {
		return this.add;
	}

	public function bindInc():Void->Void {
		return this.inc;
	}
}

class Main {
	static function main() {
		var c = new Counter(1);
		var add = c.bindAdd();
		Sys.println("a1=" + add(2));
		Sys.println("n1=" + c.n);

		var inc = c.bindInc();
		inc();
		Sys.println("n2=" + c.n);

		c.n = 10;
		Sys.println("a2=" + add(5));
		Sys.println("n3=" + c.n);
	}
}
