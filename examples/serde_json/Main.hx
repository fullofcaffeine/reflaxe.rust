import rust.serde.SerdeJson;

class Main {
	static function main(): Void {
		var person = new Person("Alice", 30);
		var json = SerdeJson.toString(person);
		Sys.println(json);
	}
}

