@:rustSupportCrate({
	name: "native_page_size_support",
	sourceRoot: "native/native_page_size_support",
	unsafePolicy: "audited",
	targets: ["*"],
	dependencies: []
})
@:native("native_page_size_support::PageSize")
extern class PageSize {
	public static function current():Int;
}

class Main {
	static function main():Void {
		PageSize.current();
	}
}
