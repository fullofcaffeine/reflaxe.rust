private class Animal {
	public final kind:String;

	public function new(kind:String) {
		this.kind = kind;
	}
}

private class Dog extends Animal {
	public final name:String;

	public function new(name:String) {
		super("dog");
		this.name = name;
	}
}

class Main {
	static function boom():Void {
		throw new Dog("fido");
	}

	static function main() {
		try {
			boom();
			Sys.println("no-throw");
		} catch (e:Animal) {
			Sys.println("animal=" + e.kind);
		} catch (e:Dynamic) {
			Sys.println("dynamic=" + Std.string(e));
		}
	}
}
