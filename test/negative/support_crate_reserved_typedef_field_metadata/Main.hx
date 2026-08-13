typedef Payload = {
	@:rustSupportCrate({name: "native_page_size_support"})
	final value:Int;
}

class Main {
	static function main():Void {
		final payload:Payload = {value: 1};
		trace(payload.value);
	}
}
