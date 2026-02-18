import rust.test.Assert;

/**
	Haxe-authored test suite for `examples/tui_todo`.

	Why
	- Migrates the former `native/tui_tests.rs` assertions to typed Haxe while still running under
	  Rust `cargo test` via `@:rustTest`.
**/
class TuiTests {
	public static function __link():Void {}

	@:rustTest
	public static function scenarioTasksRenders():Void {
		Assert.isTrue(Harness.scenarioTasksMatchesGolden(), "tasks frame should match golden");
	}

	@:rustTest
	public static function scenarioPaletteRenders():Void {
		Assert.isTrue(Harness.scenarioPaletteMatchesGolden(), "palette frame should match golden");
	}

	@:rustTest
	public static function scenarioEditTitleRenders():Void {
		Assert.isTrue(Harness.scenarioEditTitleMatchesGolden(), "edit-title frame should match golden");
	}

	@:rustTest
	public static function scenarioDashboardFxDeterministic():Void {
		Assert.isTrue(Harness.scenarioDashboardFxDeterministic(), "dashboard fx should be deterministic");
	}

	@:rustTest
	public static function persistenceRoundtrip():Bool {
		return Harness.persistenceRoundtrip();
	}

	@:rustTest
	public static function persistenceMigratesV0():Bool {
		return Harness.persistenceMigratesV0();
	}

	@:rustTest
	public static function persistenceAutosaveDebounce():Bool {
		return Harness.persistenceAutosaveDebounce();
	}

	@:rustTest
	public static function persistenceRejectsInvalidSchema():Bool {
		return Harness.persistenceRejectsInvalidSchema();
	}
}
