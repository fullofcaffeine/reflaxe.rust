enum Token {
	Payload(value:Int);
}

enum GenericToken<T> {
	Wrapped(value:T);
}

class Main {
	#if capture_constructor
	static function keepConstructor(constructor:Int->Token):Int->Token {
		return constructor;
	}

	static function returnConstructor():Int->Token {
		return Payload;
	}
	#end

	static function main():Void {
		var immediate = Payload(41);
		var parenthesized = (Payload)(42);
		var qualified = Token.Payload(43);
		var generic = GenericToken.Wrapped(44);
		var metadataWrapped = (@:noCompletion Payload)(45);
		var castWrapped = (cast Payload : Int->Token)(46);
		#if capture_constructor
		var constructor = Payload;
		var captured = constructor(42);
		var passed = keepConstructor(Payload);
		var returned = returnConstructor();
		var passedValue = passed(47);
		var returnedValue = returned(48);
		#end
	}
}
