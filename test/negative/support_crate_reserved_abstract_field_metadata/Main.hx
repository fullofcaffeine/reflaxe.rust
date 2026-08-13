abstract Wrapped(Int) {
	@:rustSupportCrate({name: "native_page_size_support"})
	public static function helper():Int
		return 1;
}

class Main {
	static function main():Void
		trace(Wrapped.helper());
}
