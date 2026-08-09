class Main {
	static function main():Void {
		// π keeps this contract honest about UTF-8 source coordinates.
		#if position_date_tools
		var parsed = DateTools.parse(86400000);
		if (parsed.days == -1) {}
		#elseif position_concurrent
		var mutex = rust.concurrent.Mutexes.create(1);
		if (mutex == null) {}
		#else
		var setting = Sys.getEnv("κλειδί");
		if (setting != null && setting.length == -1) {}
		#end
	}
}
