import haxe.ds.Option;
import haxe.functional.Result;
import haxe.io.Bytes;

class Foo {
	public var x: Int;

	public function new(x: Int) {
		this.x = x;
	}
}

enum MyEnum {
	A;
	B(v: Int);
}

class Main {
	static function main(): Void {
		trace("--- Std.string ---");
		trace(Std.string(1));
		trace(Std.string(true));
		trace(Std.string(1.5));
		trace(Std.string("hi"));
		trace(Std.string(new Foo(3)));

		trace("--- Std.parseFloat ---");
		trace(Std.parseFloat("1.25"));
		trace(Std.parseFloat("nope"));

		trace("--- Type names ---");
		trace(Type.getClassName(Foo));
		trace(Type.getEnumName(MyEnum));

		trace("--- Bytes ---");
		var b = Bytes.ofString("hi");
		trace(b.length);
		trace(b.get(0));
		b.set(0, 72);
		trace(b.toString());

		var b2 = Bytes.alloc(3);
		b2.set(0, 65);
		b2.set(1, 66);
		b2.set(2, 67);
		trace(b2.toString());

		trace("--- Option ---");
		var o: Option<Int> = Some(5);
		switch (o) {
			case Some(v): trace(v);
			case None: trace("none");
		}
		var o2: Option<Int> = None;
		switch (o2) {
			case Some(v): trace(v);
			case None: trace("none");
		}

		trace("--- Result ---");
		var r: Result<Int, String> = Ok(7);
		switch (r) {
			case Ok(v): trace(v);
			case Error(e): trace(e);
		}
		var r2: Result<Int, String> = Error("fail");
		switch (r2) {
			case Ok(v): trace(v);
			case Error(e): trace(e);
		}

		trace("--- Reflect ---");
		var foo = new Foo(9);
		trace(foo.x);
		trace(Reflect.field(foo, "x"));
		Reflect.setField(foo, "x", 42);
		trace(foo.x);
	}
}

