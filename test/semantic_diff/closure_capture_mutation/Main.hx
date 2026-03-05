class Main {
	static function main() {
		var x = 0;
		var readX = function():Int return x;
		x = 7;
		Sys.println("after_set=" + readX());

		var y = 1;
		var incY = function():Void y++;
		var readY = function():Int return y;
		incY();
		incY();
		Sys.println("after_inc=" + readY());

		var z = 10;
		var addZ = function(delta:Int):Int {
			z += delta;
			return z;
		};
		Sys.println("z_from_closure=" + addZ(5));
		Sys.println("z_outer=" + z);
	}
}
