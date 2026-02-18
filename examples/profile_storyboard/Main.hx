/**
	Profile storyboard demo entrypoint.

	Runs the same scripted board scenario across all profile variants and prints deterministic output.
**/
class Main {
	static function main() {
		StoryboardTests.__link();
		Sys.println(Harness.scenarioOutput());
	}
}
