import haxe.io.Bytes;

class Main {
	static function main(): Void {
		var b = Bytes.ofString("hello");
		var out = Bytes.alloc(5);
		out.blit(0, b, 0, 5);
		Sys.println(out.toString());
	}
}

