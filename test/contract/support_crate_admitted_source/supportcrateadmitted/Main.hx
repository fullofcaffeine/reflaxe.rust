package supportcrateadmitted;

@:rustSupportCrate({
	name: "sample_support",
	sourceRoot: "native/sample_support",
	unsafePolicy: "forbid",
	targets: ["*"],
	dependencies: []
})
@:native("sample_support::Api")
extern class SampleSupportApi {
	public static function answer():Int;
}

final class Main {
	static function main():Void {
		SampleSupportApi.answer();
	}
}
