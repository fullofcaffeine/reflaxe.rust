class Main {
	static function forward<T>(iterator:KeyValueIterator<Int, T>):KeyValueIterator<Int, T> {
		return iterator;
	}

	static function consume(iterator:KeyValueIterator<Int, String>):String {
		var values:Array<String> = [];
		while (iterator.hasNext()) {
			var item = iterator.next();
			values.push(item.key + ":" + item.value);
		}
		return values.join(",");
	}

	static function describe(item:{key:Int, value:String}):String {
		return item.key + ":" + item.value;
	}

	static function main() {
		var evaluations = 0;
		function source():Array<String> {
			evaluations++;
			return ["alpha", "beta", "gamma"];
		}

		var concrete = source().keyValueIterator();
		var iterator = forward(concrete);
		var alias = iterator;

		Sys.println("evaluations=" + evaluations);
		Sys.println("first=" + describe(iterator.next()));
		Sys.println("second=" + describe(alias.next()));
		Sys.println("rest=" + consume(iterator));
		Sys.println("hasNext=" + alias.hasNext());
	}
}
