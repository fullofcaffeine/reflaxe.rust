import rust.test.Assert;

/**
	Haxe-authored Rust tests for `examples/metal_first_dataflow`.
**/
class MetalFirstTests {
	public static function __link():Void {}

	@:rustTest
	public static function validPathUsesMetalFlow():Void {
		var joined = Harness.runValid().join("|");
		Assert.contains(joined, "count=6", "valid path should report parsed count");
		Assert.contains(joined, "peak=42", "valid path should compute peak");
		Assert.contains(joined, "sig=", "valid path should emit deterministic signature");
	}

	@:rustTest
	public static function invalidPathReturnsTypedError():Void {
		Assert.equalsString("error=invalid-int:oops", Harness.runInvalid(), "invalid token should surface typed Result error");
	}
}
