import haxe.io.Bytes;

class Main {
	static function main() {
		var filled = Bytes.alloc(4);
		filled.fill(0, 4, 0x2A);
		var fromHex = Bytes.ofHex("2a2a2a2a");
		Sys.println("compare=" + filled.compare(fromHex));
		Sys.println("hex=" + filled.toHex());

		var ints = Bytes.alloc(6);
		ints.setUInt16(0, 0x1234);
		ints.setInt32(2, 0x01020304);
		Sys.println("u16=" + ints.getUInt16(0));
		Sys.println("i32=" + ints.getInt32(2));

		var floats = Bytes.alloc(12);
		floats.setFloat(0, 1.5);
		floats.setDouble(4, 3.25);
		Sys.println("f=" + floats.getFloat(0));
		Sys.println("d=" + floats.getDouble(4));

		var text = Bytes.ofString("sunset");
		Sys.println("read=" + text.getString(1, 3));
	}
}
