class Main {
	static function main() {
		var a:Animal = new Dog();
		trace(Std.isOfType(a, Animal));
		trace(Std.isOfType(a, Dog));
		trace(Std.isOfType(a, Pet));

		var dynDog:Dynamic = new Dog();
		trace(Std.isOfType(dynDog, Animal));
		trace(Std.isOfType(dynDog, Dog));
		trace(Std.isOfType(dynDog, Pet));

		var asPet:Pet = new Dog();
		var dynPet:Dynamic = asPet;
		trace(Std.isOfType(dynPet, Pet));
		trace(Std.isOfType(dynPet, Animal));

		var dynEnum:Dynamic = Mood.Caffeinated;
		trace(Std.isOfType(dynEnum, Mood));
		trace(Std.isOfType(dynEnum, Animal));
	}
}
