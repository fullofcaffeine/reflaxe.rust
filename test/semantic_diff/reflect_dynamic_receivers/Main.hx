class Person {
	public var name:String;

	public function new(name:String) {
		this.name = name;
	}

	public function greet():String {
		return "hi " + name;
	}
}

class Main {
	static function main() {
		var person = new Person("Ada");
		Sys.println("class.name.has=" + Reflect.hasField(person, "name"));
		Sys.println("class.greet.has=" + Reflect.hasField(person, "greet"));
		Sys.println("class.name=" + Std.string(Reflect.field(person, "name")));
		Reflect.setField(person, "name", "Bea");
		Sys.println("class.name.after=" + person.name);

		var anon:Dynamic = {count: 1};
		Sys.println("anon.count.has=" + Reflect.hasField(anon, "count"));
		Sys.println("anon.count=" + Std.string(Reflect.field(anon, "count")));
		Reflect.setField(anon, "count", 2);
		Sys.println("anon.count.after=" + Std.string(Reflect.field(anon, "count")));

		var parsed:Dynamic = haxe.Json.parse('{"label":"ok","n":3}');
		Sys.println("json.label.has=" + Reflect.hasField(parsed, "label"));
		Sys.println("json.label=" + Std.string(Reflect.field(parsed, "label")));
		Reflect.setField(parsed, "n", 4);
		Sys.println("json.n.after=" + Std.string(Reflect.field(parsed, "n")));
	}
}
