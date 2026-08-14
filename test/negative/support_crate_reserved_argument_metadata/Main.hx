class Main {
	static function helper(@:rustSupportCrate({name: "native_page_size_support"}) value:Int):Int
		return value;

	static function main():Void
		trace(helper(1));
}
