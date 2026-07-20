class ExternalThrow {
	public function new() {
		// π makes character and UTF-8 byte offsets different before the operation.
		throw "βλάβη";
	}

	static function main():Void {
		new ExternalThrow();
	}
}
