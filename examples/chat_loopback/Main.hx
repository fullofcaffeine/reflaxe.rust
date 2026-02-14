class Main {
	static function main():Void {
		Harness.__link();

		var profile = Harness.profileName();
		var transcript = Harness.runTranscript();
		Sys.println("profile=" + profile);
		Sys.println(transcript);

		if (!Harness.transcriptHasExpectedShape()) {
			throw "transcript shape mismatch";
		}
		if (!Harness.parserRejectsInvalidCommand()) {
			throw "invalid command should be rejected";
		}
		if (!Harness.codecRoundtripWorks()) {
			throw "codec roundtrip failed";
		}

		Sys.println("ok");
	}
}
