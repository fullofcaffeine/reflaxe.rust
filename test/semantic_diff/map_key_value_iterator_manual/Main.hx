class Main {
	static function main() {
		var map:Map<String, Int> = ["a" => 1, "b" => 2, "c" => 3];
		var it = new haxe.iterators.MapKeyValueIterator<String, Int>(map);
		var parts = [];
		var total = 0;
		while (it.hasNext()) {
			var kv = it.next();
			parts.push(kv.key + ":" + kv.value);
			total += kv.value;
		}
		parts.sort(function(a:String, b:String):Int {
			return a < b ? -1 : (a > b ? 1 : 0);
		});
		Sys.println(parts.join(","));
		Sys.println("total=" + total);
	}
}
