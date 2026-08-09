class NativeBorrow {
	static function inspect(_value:Dynamic):Void {}

	static function reject(borrowed:rust.Ref<rust.net.TcpStream>):Void {
		inspect(borrowed);
	}

	static function main():Void {}
}
