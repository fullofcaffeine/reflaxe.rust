import rust.test.Assert;

/**
	Haxe-authored Rust tests for `examples/bytes_ops`.
**/
class BytesTests {
	public static function __link():Void {}

	@:rustTest
	public static function bytesGetSetSubGetStringBlit():Void {
		Assert.isTrue(Harness.bytesGetSetSubGetStringBlit(), "bytes primitive operations should remain stable");
	}

	@:rustTest
	public static function bytesOutOfBoundsIsCatchable():Void {
		Assert.isTrue(Harness.bytesOutOfBoundsIsCatchable(), "bytes oob should throw catchable haxe.io.Error");
	}
}
