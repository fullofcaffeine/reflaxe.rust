import haxe.io.BytesBuffer;
import haxe.io.Error;

class Main {
	static function main(): Void {
		var bb = new BytesBuffer();
		bb.addString("Hi");
		bb.addByte(" ".code);
		bb.addString("Rust");
		bb.addByte("!".code);
		Sys.println(bb.length);
		Sys.println(bb.getBytes().toString());

		// Bounds behavior: addBytes out of range should throw OutsideBounds and be catchable by type.
		var bb2 = new BytesBuffer();
		try {
			bb2.addBytes(haxe.io.Bytes.ofString("abc"), 0, 999);
			Sys.println("nope");
		} catch (e:Error) {
			Sys.println(Std.string(e));
		}
	}
}

