class Main {
	@:rustSupportCrate({
		name: "native_page_size_support",
		sourceRoot: "native/native_page_size_support",
		unsafePolicy: "audited",
		targets: ["aarch64-apple-darwin", "x86_64-apple-darwin"],
		dependencies: []
	})
	static function main():Void {}
}
