class Main {
	static function main():Void {
		final value = @:rustSupportCrate({name: "native_page_size_support"}) 1;
		trace(value);
	}
}
