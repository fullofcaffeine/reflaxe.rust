class Main {
	static function callTwice(f:Void->Void):Void {
		f();
		f();
	}

	static function relay(f:Void->Void):Void->Void {
		return f;
	}

	static function applyPair(f:Int->Void):Void {
		f(5);
		f(7);
	}

	static function main() {
		var x = 0;
		var inc = function():Void x++;
		callTwice(inc);
		var forwarded = relay(inc);
		forwarded();
		Sys.println("x=" + x);

		var y = 10;
		var add = function(delta:Int):Void y += delta;
		applyPair(add);
		var stored = add;
		stored(3);
		Sys.println("y=" + y);

		var z = 1;
		var mk = function():Int->Int {
			return function(delta:Int):Int {
				z += delta;
				return z;
			};
		};
		var next = mk();
		Sys.println("z1=" + next(4));
		Sys.println("z2=" + next(2));
		Sys.println("z_outer=" + z);
	}
}
