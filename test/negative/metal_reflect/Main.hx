class Main {
	static function main() {
		var payload = {id: 7, name: "metal"};
		var value:String = cast Reflect.field(payload, "name");
		trace(value);
	}
}
