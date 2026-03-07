import haxe.http.HttpBase;
import haxe.io.Bytes;

class ProbeHttp extends HttpBase {
	public var seenData:Array<String> = [];
	public var seenBytes:Array<Int> = [];

	public function new() {
		super("http://example.test/");
	}

	public function emit(data:String):Void {
		success(Bytes.ofString(data));
	}

	override function onData(data:String):Void {
		seenData.push(data);
	}

	override function onBytes(data:Bytes):Void {
		seenBytes.push(data.length);
	}
}

class Main {
	static function main():Void {
		var http = new ProbeHttp();
		http.emit("ok");
		Sys.println(http.seenData.join(",") + "|" + http.seenBytes.join(","));
	}
}
