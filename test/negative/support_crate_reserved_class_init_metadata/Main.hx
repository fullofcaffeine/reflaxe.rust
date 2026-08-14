class Main {
	static function __init__():Void {
		function identity<@:rustSupportCrate({name: "native_page_size_support"}) T>(value:T):T
			return value;
		identity(1);
	}

	static function main():Void {}
}
