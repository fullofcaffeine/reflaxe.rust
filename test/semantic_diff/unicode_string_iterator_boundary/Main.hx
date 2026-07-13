import haxe.iterators.StringIteratorUnicode;
import haxe.iterators.StringKeyValueIteratorUnicode;

class Main {
	static function forwardValues<T>(iterator:Iterator<T>):Iterator<T> {
		return iterator;
	}

	static function forwardPairs<K, V>(iterator:KeyValueIterator<K, V>):KeyValueIterator<K, V> {
		return iterator;
	}

	static function consumeValues(iterator:Iterator<Int>):String {
		var values:Array<Int> = [];
		while (iterator.hasNext()) {
			values.push(iterator.next());
		}
		return values.join(",");
	}

	static function consumePairs(iterator:KeyValueIterator<Int, Int>):String {
		var values:Array<String> = [];
		while (iterator.hasNext()) {
			var item = iterator.next();
			values.push(item.key + ":" + item.value);
		}
		return values.join(",");
	}

	static function main() {
		var evaluations = 0;
		function source():String {
			evaluations++;
			return "Aé🙂中";
		}

		var concreteValues = StringIteratorUnicode.unicodeIterator(source());
		var values = forwardValues(concreteValues);
		var valuesAlias = values;

		var concretePairs = StringKeyValueIteratorUnicode.unicodeKeyValueIterator(source());
		var pairs = forwardPairs(concretePairs);
		var pairsAlias = pairs;

		Sys.println("evaluations=" + evaluations);
		Sys.println("valueFirst=" + values.next());
		Sys.println("valueSecond=" + valuesAlias.next());
		Sys.println("valueRest=" + consumeValues(values));
		Sys.println("valuesHasNext=" + valuesAlias.hasNext());

		var firstPair = pairs.next();
		var secondPair = pairsAlias.next();
		Sys.println("pairFirst=" + firstPair.key + ":" + firstPair.value);
		Sys.println("pairSecond=" + secondPair.key + ":" + secondPair.value);
		Sys.println("pairRest=" + consumePairs(pairs));
		Sys.println("pairsHasNext=" + pairsAlias.hasNext());
	}
}
