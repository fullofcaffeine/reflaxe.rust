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

	@:rustTest
	public static function historyPresenceSyncWorks():Void {
		Assert.isTrue(Harness.historyPresenceSyncWorks(), "history refresh should sync remote operators into the UI list");
	}

	@:rustTest
	public static function diagnosticsPanelShowsSignals():Void {
		Assert.isTrue(Harness.diagnosticsPanelShowsSignals(), "diagnostics panel should render typed runtime/action signals");
	}

	@:rustTest
	public static function channelIsolationAndActivityLogWorks():Void {
		Assert.isTrue(Harness.channelIsolationAndActivityLogWorks(), "timeline should filter by channel and activity log should show online/offline markers");
	}

	@:rustTest
	public static function historySnapshotsAvoidSpamLines():Void {
		Assert.isTrue(Harness.historySnapshotsAvoidSpamLines(), "history snapshots should import new messages without timeline spam");
	}

	@:rustTest
	public static function chatServerLogsQuietByDefault():Void {
		Assert.isTrue(Harness.chatServerLogsAreQuietByDefault(), "chat server logs must stay disabled by default to keep TUI output stable");
	}

	@:rustTest
	public static function remoteRealtimeFlowStable():Void {
		Assert.isTrue(Harness.remoteRealtimeFlowStable(), "remote runtime should keep multi-client polling stable and reflect new messages");
	}

	@:rustTest
	public static function generatedIdentityVariesAcrossCalls():Void {
		Assert.isTrue(Harness.generatedIdentityVariesAcrossCalls(), "auto identity generation should not reuse a constant seed");
		Assert.isTrue(Harness.foldedIdentitySeedAvoidsSaturation(), "time folding should avoid Int saturation collisions");
	}
}
