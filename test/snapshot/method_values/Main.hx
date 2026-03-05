class Base {
	public function new() {}

	public function f(x:Int):Int {
		return x + 1;
	}
}

class Sub extends Base {
	public function new() {
		super();
	}

	override public function f(x:Int):Int {
		return x + 2;
	}
}

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
		var c = new Counter(0);

		var add = c.add;
		trace(add(2));
		trace(c.n);

		var inc = c.inc;
		inc();
		trace(c.n);

		var addFromThis = c.bindAdd();
		trace(addFromThis(3));
		trace(c.n);

		var incFromThis = c.bindInc();
		incFromThis();
		trace(c.n);

		var b:Base = new Sub();
		var bf = b.f;
		trace(bf(5));
	}
}
