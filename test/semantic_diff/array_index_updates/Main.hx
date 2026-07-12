class Main {
	static var ints:Array<Int> = [10, 20];
	static var floats:Array<Float> = [1.5];
	static var arrayCalls = 0;
	static var indexCalls = 0;

	static function intArray():Array<Int> {
		arrayCalls = arrayCalls + 1;
		return ints;
	}

	static function floatArray():Array<Float> {
		arrayCalls = arrayCalls + 1;
		return floats;
	}

	static function index(value:Int):Int {
		indexCalls = indexCalls + 1;
		return value;
	}

	static function mutatingDelta():Int {
		ints[0] = 100;
		return 5;
	}

	static function main() {
		Sys.println("int-post-inc-result=" + intArray()[index(1)]++);
		Sys.println("int-post-inc-value=" + ints[1]);
		Sys.println("int-pre-inc-result=" + ++intArray()[index(1)]);
		Sys.println("int-pre-inc-value=" + ints[1]);
		Sys.println("int-post-dec-result=" + intArray()[index(1)]--);
		Sys.println("int-post-dec-value=" + ints[1]);
		Sys.println("int-pre-dec-result=" + --intArray()[index(1)]);
		Sys.println("int-pre-dec-value=" + ints[1]);
		Sys.println("float-post-result=" + floatArray()[index(0)]++);
		Sys.println("float-post-value=" + floats[0]);
		Sys.println("float-pre-result=" + ++floatArray()[index(0)]);
		Sys.println("float-pre-value=" + floats[0]);
		Sys.println("int-assignop-result=" + (intArray()[index(0)] += mutatingDelta()));
		Sys.println("int-assignop-value=" + ints[0]);
		Sys.println("array-calls=" + arrayCalls);
		Sys.println("index-calls=" + indexCalls);
	}
}
