import rust.test.Assert;

/**
	Haxe-authored Rust test suite for `examples/chat_loopback`.

	Why
	- Exercises the `@:rustTest` flow end-to-end: tests are authored in typed Haxe and emitted as
	  Rust `#[test]` wrappers.
	- Keeps the flagship app covered at both protocol and TUI layers.
**/
class ChatTests {
	public static function __link():Void {}

	@:rustTest
	public static function transcriptShapeAndProfileMarker():Void {
		Assert.isTrue(Harness.transcriptHasExpectedShape(), "transcript shape mismatch");

		var profile = Harness.profileName();
		var transcript = Harness.runTranscript();
		var lines = transcript.split("\n");

		Assert.equalsInt(4, lines.length, "transcript line count");
		Assert.startsWith(lines[3], "BYE|", "final line");
		Assert.contains(lines[3], profile, "profile marker");
	}

	@:rustTest
	public static function parserAndCodecContracts():Void {
		Assert.isTrue(Harness.parserRejectsInvalidCommand(), "invalid command should be rejected");
		Assert.isTrue(Harness.codecRoundtripWorks(), "codec roundtrip should succeed");
	}

	@:rustTest({name: "chat_profile_is_supported"})
	public static function profileIsSupportedVariant():Bool {
		var profile = Harness.profileName();
		return profile == "portable" || profile == "idiomatic" || profile == "rusty" || profile == "metal";
	}

	@:rustTest
	public static function showcaseLayoutLooksModern():Void {
		Assert.isTrue(Harness.showcaseHasExpectedLayout(), "showcase layout should expose all key panes");
	}

	@:rustTest
	public static function helpModalAndInputFlow():Void {
		Assert.isTrue(Harness.helpModalVisible(), "help modal should render cheat-sheet commands");
		Assert.isTrue(Harness.interactiveInputFlowWorks(), "typed input should be visible in timeline");
	}

	@:rustTest
	public static function pulseSceneIsDeterministic():Void {
		Assert.isTrue(Harness.pulseSceneDeterministic(), "animation scene should be deterministic under fixed ticks");
	}
}
