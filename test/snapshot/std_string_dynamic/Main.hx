class Foo {
	public var x:Int;

	public function new(x:Int)
		this.x = x;
}

class Main {
	static function main() {
		trace("--- Std.string primitives ---");
		trace(Std.string(1));
		trace(Std.string(true));
		trace(Std.string(1.5));
		trace(Std.string("hi"));

		trace("--- Std.string array ---");
		var xs = [1, 2, 3];
		trace(Std.string(xs));
		trace(xs.toString());

		trace("--- Std.string object ---");
		var foo = new Foo(3);
		trace(Std.string(foo));

		trace("--- Sys.println untyped values ---");
		Sys.println(foo);
		var n:Null<Int> = null;
		Sys.println(n);
		n = 5;
		Sys.println(n);
	}
}
