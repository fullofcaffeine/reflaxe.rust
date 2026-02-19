import haxe.io.Bytes;
import haxe.io.Error;

/**
	Deterministic harness for `examples/bytes_ops`.
**/
class Harness {
	public static function baselineOutput():String {
		var b = Bytes.ofString("hello");
		var out = Bytes.alloc(5);
		out.blit(0, b, 0, 5);
		return out.toString();
	}

	public static function bytesGetSetSubGetStringBlit():Bool {
		var b = Bytes.ofString("hello");
		if (b.length != 5) {
			return false;
		}
		if (b.get(0) != "h".code) {
			return false;
		}
		var part = b.getString(1, 3);
		if (part.length != 3 || part.charCodeAt(0) != "e".code || part.charCodeAt(1) != "l".code || part.charCodeAt(2) != "l".code) {
			return false;
		}
		var sub = b.sub(1, 3);
		if (sub.length != 3 || sub.get(0) != "e".code || sub.get(1) != "l".code || sub.get(2) != "l".code) {
			return false;
		}

		var out = Bytes.alloc(5);
		out.blit(0, b, 0, 5);
		if (out.get(0) != "h".code || out.get(1) != "e".code || out.get(2) != "l".code || out.get(3) != "l".code || out.get(4) != "o".code) {
			return false;
		}

		out.set(0, "H".code);
		return out.get(0) == "H".code;
	}

	public static function bytesOutOfBoundsIsCatchable():Bool {
		var b = Bytes.ofString("hi");

		var getOobCaught = false;
		try {
			b.get(99);
		} catch (e:Error) {
			getOobCaught = isOutsideBounds(e);
		}

		var blitOobCaught = false;
		var out = Bytes.alloc(2);
		try {
			out.blit(0, b, 0, 99);
		} catch (e:Error) {
			blitOobCaught = isOutsideBounds(e);
		}

		return getOobCaught && blitOobCaught;
	}

	static function isOutsideBounds(error:Error):Bool {
		return switch (error) {
			case OutsideBounds:
				true;
			case _:
				false;
		}
	}
}
