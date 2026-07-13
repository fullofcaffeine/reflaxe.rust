import haxe.DynamicAccess;

class Main {
	static function forwardValues<T>(iterator:Iterator<T>):Iterator<T> {
		return iterator;
	}

	static function forwardPairs<T>(iterator:KeyValueIterator<String, T>):KeyValueIterator<String, T> {
		return iterator;
	}

	static function main() {
		var evaluations = 0;
		function source():DynamicAccess<Int> {
			evaluations++;
			var result = new DynamicAccess<Int>();
			result["alpha"] = 7;
			return result;
		}

		var values = source();
		var concreteValues = values.iterator();
		var valueIterator = forwardValues(concreteValues);
		var valueAlias = valueIterator;

		var concretePairs = values.keyValueIterator();
		var pairIterator = forwardPairs(concretePairs);
		var pairAlias = pairIterator;

		values["alpha"] = 9;

		Sys.println("evaluations=" + evaluations);
		Sys.println("value=" + valueIterator.next());
		Sys.println("valuesHasNext=" + valueAlias.hasNext());

		var pair = pairIterator.next();
		Sys.println("pair=" + pair.key + ":" + pair.value);
		Sys.println("pairsHasNext=" + pairAlias.hasNext());
	}
}
