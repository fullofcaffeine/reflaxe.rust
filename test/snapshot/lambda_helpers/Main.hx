using Lambda;

class Main {
	static function main() {
		var a = [1, 2, 3, 4];

		var mapped = a.map(x -> x * 2);
		var filtered = a.filter(x -> x == 2 || x == 4);
		var sum = a.fold((x, acc) -> acc + x, 0);
		var total = a.count();
		var hasThree = a.exists(x -> x == 3);
		var hasFour = a.has(4);

		Sys.println(mapped.length);
		Sys.println(filtered.length);
		Sys.println(sum);
		Sys.println(total);
		Sys.println(hasThree);
		Sys.println(hasFour);
	}
}
