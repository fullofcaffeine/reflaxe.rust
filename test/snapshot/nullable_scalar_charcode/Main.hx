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
	}
}
