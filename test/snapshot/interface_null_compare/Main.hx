class Main {
	static function isMissing(value:IThing):Bool {
		return value == null;
	}

	static function isPresent(value:IThing):Bool {
		return value != null;
	}

	static function main():Void {
		var value:IThing = new Impl();
		Sys.println(isMissing(value));
		Sys.println(isPresent(value));
	}
}
