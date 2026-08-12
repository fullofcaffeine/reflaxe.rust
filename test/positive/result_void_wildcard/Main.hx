import rust.Result;

/** Package-neutral proof that a discarded `Void` enum payload becomes Rust unit. */
class Main {
	static function inspect(result:Result<Void, Int>):Bool {
		return switch result {
			case Ok(_): true;
			case Err(_): false;
		}
	}

	static function main():Void {}
}
