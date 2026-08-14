class Main {
	static function main():Void {
		trace(({
			field: 1
		} : {
			@:rustSupportCrate({name: "native_page_size_support"})
			var field:Int;
		}).field);
	}
}
