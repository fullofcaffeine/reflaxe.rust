import haxe.Json;
import haxe.Serializer;
import haxe.Unserializer;
import haxe.crypto.Base64;
import haxe.crypto.Sha256;
import haxe.io.Bytes;
import haxe.json.Value;

private typedef ObjAB = {
	var a:Int;
	var b:String;
};

class Main {
	static function main() {
		Sys.println("sha256=" + Sha256.encode("hello"));

		var b = Bytes.ofString("hi");
		Sys.println("b64=" + Base64.encode(b));

		var obj:ObjAB = {a: 1, b: "x"};
		var json = Json.stringify(obj);
		Sys.println("json=" + json);
		var parsed = Json.parseValue(json);
		var parsedA = switch (parsed) {
			case JObject(keys, values):
				var out = -1;
				var i = 0;
				while (i < keys.length) {
					if (keys[i] == "a") {
						out = switch (values[i]) {
							case JNumber(n): Std.int(n);
							case _: -1;
						};
						break;
					}
					i = i + 1;
				}
				out;
			case _: -1;
		};
		Sys.println("parsed.a=" + parsedA);

		var ser = Serializer.run(obj);
		Sys.println("ser=" + ser);
		var unser:ObjAB = cast Unserializer.run(ser);
		Sys.println("unser.b=" + unser.b);
	}
}
