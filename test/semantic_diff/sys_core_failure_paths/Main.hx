class Main {
	static function reportCaught(label:String, operation:Void->Void):Void {
		var caught = false;
		try {
			operation();
		} catch (_:Dynamic) {
			caught = true;
		}

		Sys.println(label + "_caught=" + caught);
		Sys.println(label + "_continued=true");
	}

	static function main():Void {
		reportCaught("invalid_cwd", () -> {
			Sys.setCwd(Sys.getCwd() + "/__reflaxe_rust_contract_missing__/child");
		});
	}
}
