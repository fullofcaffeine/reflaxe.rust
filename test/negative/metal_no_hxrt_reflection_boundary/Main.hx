class Main {
	static function main() {
		var payload = {name: "metal"};
		var value = Reflect.field(payload, "name");
		if (value == null) {}
	}
}
