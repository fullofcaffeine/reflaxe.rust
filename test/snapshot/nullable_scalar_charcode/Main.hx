class Main {
	static function describe(value:Null<Int>):String {
		if (value == null) {
			return "none";
		}
		return "value:" + value;
	}

	static function sameAsSeven(value:Null<Int>):Bool {
		return value == 7;
	}

	static function notSeven(value:Null<Int>):Bool {
		return value != 7;
	}

	static function quote(value:String):String {
		var out = "\"";
		for (i in 0...value.length) {
			final code = value.charCodeAt(i);
			if (code == "\"".code) {
				out += "\\\"";
			} else if (code == "\\".code) {
				out += "\\\\";
			} else if (code == "\n".code) {
				out += "\\n";
			} else if (code == "\r".code) {
				out += "\\r";
			} else if (code == "\t".code) {
				out += "\\t";
			} else {
				out += value.charAt(i);
			}
		}
		return out + "\"";
	}

	static function parseHexByte(value:String):Int {
		final parsed = Std.parseInt("0x" + value);
		if (parsed == null) {
			return -1;
		}
		return value.length == 2 ? parsed : Std.int(parsed / 257);
	}

	static function digitValue(value:String):Int {
		final code = value.charCodeAt(0);
		if (code == null) {
			return -1;
		}
		if (code >= "0".code && code <= "9".code) {
			return code - "0".code;
		}
		return -1;
	}

	static function main() {
		var n:Null<Int> = null;
		Sys.println(describe(n));
		Sys.println(sameAsSeven(n));
		Sys.println(notSeven(n));
		n = 7;
		Sys.println(describe(n));
		Sys.println(sameAsSeven(n));
		Sys.println(notSeven(n));
		Sys.println("scalar:" + n);
		Sys.println(quote("a\n\"\\\t"));
		Sys.println(parseHexByte("ff"));
		Sys.println(parseHexByte("ffff"));
		Sys.println(digitValue("7"));
		Sys.println(digitValue(""));
	}
}
