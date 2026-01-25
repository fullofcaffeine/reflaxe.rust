import haxe.ds.List;

class Main {
	static function main() {
		var l = new List<Int>();
		l.add(1);
		l.add(2);
		l.add(3);

		var sum = 0;
		for (x in l) sum += x;

		Sys.println(l.length);
		Sys.println(sum);
	}
}

