@:rustDerive(["serde::Serialize", "serde::Deserialize"])
class Person {
	public var name: String;
	public var age: Int;

	public function new(name: String, age: Int) {
		this.name = name;
		this.age = age;
	}
}

