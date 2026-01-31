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

		Sys.println(a == b);
		Sys.println(a == c);
		Sys.println(a != b);

		var xs1 = [1, 2];
		var xs2 = [1, 2];
		var xs3 = xs1;

		Sys.println(xs1 == xs2);
		Sys.println(xs1 == xs3);
		Sys.println(xs1 != xs2);
	}
}
