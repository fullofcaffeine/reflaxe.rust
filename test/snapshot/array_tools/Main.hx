using ArrayTools;

class Main {
	static function main() {
		var a = [1, 2, 3, 4];

		var mapped = a.map(x -> x * 2);
		var filtered = a.filter(x -> x > 2);
		var hasThree = a.exists(x -> x == 3);
		var foundTwo = a.find(x -> x == 2);
		var sum = a.fold((x, acc) -> acc + x, 0);

		Sys.println(mapped.length);
		Sys.println(filtered.length);
		Sys.println(hasThree);
		Sys.println(foundTwo == null);
		Sys.println(sum);
	}
}

