import haxe.io.Bytes;
import haxe.io.Error;

class Main {
	static function main(): Void {
		var b = Bytes.ofString("hello");
		trace(b.toString());

		var s = b.sub(1, 3);
		trace(s.toString());

		var out = Bytes.alloc(5);
		out.blit(0, b, 0, 5);
		trace(out.toString());

		out.set(0, "H".code);
		trace(out.get(0));
		trace(out.getString(0, 2));

		try out.get(999) catch (e:Error) trace(e);

		try out.blit(0, b, 0, 999) catch (e:Error) trace(e);
	}
}
