class Main {
	static function main():Void {
		function identity<@:rustSupportCrate({name: "native_page_size_support"}) T>(value:T):T
			return value;
		trace(identity(1));
	}
}
