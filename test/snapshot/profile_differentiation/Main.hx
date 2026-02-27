class Main {
	static function main() {
		var banner:Null<String> = null;
		var count = 1;
		var frozen = count + 1;
		var total = 0;
		var numbers = [1, 2, 3];
		numbers.push(4);
		for (n in numbers) {
			total += n;
		}
		trace(banner);
		trace(frozen);
		trace(total);
	}
}
