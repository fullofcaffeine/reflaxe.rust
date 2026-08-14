interface Comparable<T> {}

class Box<@:rustSupportCrate({name: "native_page_size_support"}) T:Comparable<T>> {
	public function new() {}
}

class Main {
	static function main():Void {}
}
