class Main {
	static function main() {
		var a:Animal = new Dog();
		trace(Std.isOfType(a, Animal));
		trace(Std.isOfType(a, Dog));
		trace(Std.isOfType(a, Pet));
		trace(Std.isOfType(a, Friendly));

		var dynDog:Dynamic = new Dog();
		trace(Std.isOfType(dynDog, Animal));
		trace(Std.isOfType(dynDog, Dog));
		trace(Std.isOfType(dynDog, Pet));
		trace(Std.isOfType(dynDog, Friendly));

		var asPet:Pet = new Dog();
		var dynPet:Dynamic = asPet;
		trace(Std.isOfType(dynPet, Pet));
		trace(Std.isOfType(dynPet, Animal));
		trace(Std.isOfType(dynPet, Friendly));

		var asFriendly:Friendly = new Dog();
		var dynFriendly:Dynamic = asFriendly;
		trace(Std.isOfType(dynFriendly, Pet));
		trace(Std.isOfType(dynFriendly, Friendly));
		trace(Std.isOfType(dynFriendly, Animal));

		var dynEnum:Dynamic = Mood.Caffeinated;
		trace(Std.isOfType(dynEnum, Mood));
		trace(Std.isOfType(dynEnum, Animal));
	}
}
