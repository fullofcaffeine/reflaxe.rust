import rust.test.Assert;

/**
	Haxe-authored Rust tests for `examples/profile_storyboard`.

	Why
	- This example is the canonical small reference for profile-style differences (`portable`,
	  `idiomatic`, `rusty`, `metal`) on one shared domain model.
	- Tests intentionally stay in typed Haxe to model how backend users should author app tests.

	What
	- Uses `@:rustTest` to mark `public static` methods as Rust test wrappers.
	- Covers scenario shape, move semantics, and profile marker validity.

	How
	- The compiler collects these methods and emits `#[test]` wrappers in `main.rs`.
	- Return `Void` for assertion-style tests and `Bool` for direct wrapper `assert!(...)` checks.
	- Metadata object form (`@:rustTest({ name, serial })`) is demonstrated below.
**/
class StoryboardTests {
	public static function __link():Void {}

	/**
		Reference `@:rustTest` contract example.

		Why
		- Demonstrates the verbose metadata form in an example test suite so profile authors can
		  copy a documented pattern.

		What
		- `name` sets a stable Rust test function name.
		- `serial` keeps this test on the shared lock (default is `true`, included here explicitly
		  for readability).

		How
		- This test validates only profile-agnostic scenario shape, so it should pass under every
		  profile compile file for this example.
	**/
	@:rustTest({name: "storyboard_report_shape", serial: true})
	public static function reportShapeAcrossProfiles():Void {
		Assert.isTrue(Harness.reportHasExpectedShape(), "report shape should match storyboard contract");
	}

	@:rustTest
	public static function moveFlowRemainsStable():Void {
		Assert.isTrue(Harness.moveFlowWorks(), "move flow should preserve done-lane membership");
	}

	@:rustTest({serial: false})
	public static function riskDigestIncludesCardCount():Void {
		Assert.isTrue(Harness.riskDigestHasCardCount(), "risk digest should include profile and card count");
	}

	@:rustTest
	public static function profileDefineIsSupported():Bool {
		var profile = Harness.profileName();
		return profile == "portable" || profile == "idiomatic" || profile == "rusty" || profile == "metal";
	}
}
