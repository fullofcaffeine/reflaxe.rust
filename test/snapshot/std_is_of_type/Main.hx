class Main {
	static function main() {
		var a:Animal = new Dog();
		trace(Std.isOfType(a, Animal));
		trace(Std.isOfType(a, Dog));

		var dynDog:Dynamic = new Dog();
		trace(Std.isOfType(dynDog, Animal));
		trace(Std.isOfType(dynDog, Dog));

		var dynEnum:Dynamic = Mood.Caffeinated;
		trace(Std.isOfType(dynEnum, Mood));
		trace(Std.isOfType(dynEnum, Animal));
	}
}
