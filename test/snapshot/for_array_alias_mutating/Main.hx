class Main {
	static function main() {
		var xs = [1, 2, 3];
		var ys = xs;
		var sum = 0;
		for (x in xs) {
			sum += x;
			if (x == 2) {
				ys.push(9);
			}
		}
		trace(sum);
	}
}
