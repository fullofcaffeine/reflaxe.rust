import haxe.Json;
import haxe.Serializer;
import haxe.Unserializer;
import haxe.crypto.Base64;
import haxe.crypto.Sha256;
import haxe.io.Bytes;

class Main {
	static function main() {
		Sys.println("sha256=" + Sha256.encode("hello"));

		var b = Bytes.ofString("hi");
		Sys.println("b64=" + Base64.encode(b));

		var obj = {a: 1, b: "x"};
		var json = Json.stringify(obj);
		Sys.println("json=" + json);
		var parsed:Dynamic = Json.parse(json);
		Sys.println("parsed.a=" + Reflect.field(parsed, "a"));

		var ser = Serializer.run(obj);
		Sys.println("ser=" + ser);
		var unser:Dynamic = Unserializer.run(ser);
		Sys.println("unser.b=" + Reflect.field(unser, "b"));
	}
}
