class Main {
	static function boom(kind:Int):Void {
		switch kind {
			case 0:
				throw "str";
			case 1:
				throw 7;
			default:
				throw "unknown";
		}
	}

	static function main() {
		for (kind in 0...2) {
			try {
				boom(kind);
				Sys.println("ok");
			} catch (e:String) {
				Sys.println("str=" + e);
			} catch (e:Dynamic) {
				Sys.println("dyn=" + Std.string(e));
			}
		}
	}
}
