class Main {
	static function main():Void {
		var value:{
			@:rustSupportCrate({name: "native_page_size_support"})
			var field:Int;
		} = {field: 1};
		trace(value.field);
	}
}
