class Main {
	static function main():Void {
		var x = try {
			throw "boom";
			1;
		} catch (e:Dynamic) {
			2;
		}
		trace(x);
	}
}

