class Foo {
	public var n:Int;

	public function new(n:Int) {
		this.n = n;
	}
}

class Main {
	static function main() {
		var a = new Foo(1);
		var b = new Foo(1);
		var c = a;

		var xs = [a, b, c];

		Sys.println(xs.contains(a));
		Sys.println(xs.contains(new Foo(1)));

		Sys.println(xs.indexOf(a));
		Sys.println(xs.indexOf(new Foo(1)));

		Sys.println(xs.lastIndexOf(a));
		Sys.println(xs.lastIndexOf(new Foo(1)));

		Sys.println(xs.remove(new Foo(1)));
		Sys.println(xs.remove(a));
		Sys.println(xs.length);
	}
}
