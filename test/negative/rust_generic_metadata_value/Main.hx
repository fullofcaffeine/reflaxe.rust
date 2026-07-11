class Main {
	@:rustGeneric(42)
	static function identity<T>(value:T):T {
		return value;
	}

	static function main():Void {
		trace(identity(1));
	}
}
