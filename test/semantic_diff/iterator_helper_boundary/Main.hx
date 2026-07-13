class Main {
	static function forward<T>(iterator:Iterator<T>):Iterator<T> {
		return iterator;
	}

	static function consume(iterator:Iterator<Int>):String {
		var values:Array<Int> = [];
		while (iterator.hasNext()) {
			values.push(iterator.next());
		}
		return values.join(",");
	}

	static function main() {
		var evaluations = 0;
		function source():Array<Int> {
			evaluations++;
			return [3, 4];
		}

		var concrete = source().iterator();
		var iterator = forward(concrete);

		Sys.println("evaluations=" + evaluations);
		Sys.println("first=" + iterator.next());
		Sys.println("rest=" + consume(iterator));
		Sys.println("hasNext=" + iterator.hasNext());
	}
}
