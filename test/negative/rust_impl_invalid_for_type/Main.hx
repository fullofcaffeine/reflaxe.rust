@:rustImpl({
	trait: "std::marker::Unpin",
	forType: "Vec<"
})
class Target {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

class Main {
	static function main():Void {
		var target = new Target(1);
		trace(target.value);
	}
}
