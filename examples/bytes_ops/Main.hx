import haxe.io.Bytes;

class Main {
	static function main():Void {
		BytesTests.__link();
		Sys.println(Harness.baselineOutput());
	}
}
