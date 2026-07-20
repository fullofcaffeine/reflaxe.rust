class GenericBorrow {
	static function inspect(_value:Dynamic):Void {}

	static function reject<T>(borrowed:rust.Ref<T>):Void {
		inspect(borrowed);
	}

	static function main():Void {}
}
