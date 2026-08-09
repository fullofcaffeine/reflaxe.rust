class ExternalTry {
	static function main():Void {
		// λ makes character and UTF-8 byte offsets different before the operation.
		try {
			throw "σφάλμα";
		} catch (_:String) {}
	}
}
