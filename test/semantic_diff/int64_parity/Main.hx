import haxe.Int64;

class Main {
	static function main() {
		var a = Int64.make(0x00000001, 0x00000002);
		var b = Int64.ofInt(-7);
		var c = Int64.parseString("1234567890123");
		var d = Int64.fromFloat(1024.75);
		var sum = a + b;
		var diff = a - b;
		var prod = Int64.ofInt(1234) * Int64.ofInt(-5);
		var div = Int64.parseString("1000") / Int64.ofInt(7);
		var mod = Int64.parseString("1000") % Int64.ofInt(7);
		var shl = Int64.ofInt(3) << 34;
		var shr = Int64.make(-1, 0) >> 4;
		var ushr = Int64.make(-1, -1) >>> 4;
		var anded = Int64.parseString("255") & Int64.parseString("15");
		var xored = Int64.parseString("255") ^ Int64.parseString("240");
		var neg = -Int64.ofInt(9);
		var dm = Int64.divMod(Int64.parseString("-999"), Int64.ofInt(13));
		var cmp = Int64.compare(Int64.ofInt(-2), Int64.ofInt(5));
		var ucmp = Int64.ucompare(Int64.make(-1, -1), Int64.ofInt(5));
		var toInt = Int64.toInt(Int64.ofInt(42));
		var copied = Int64.make(12, 34).copy();
		var isNeg = Int64.isNeg(b);
		var isZero = Int64.isZero(Int64.ofInt(0));
		var isInt64 = Int64.isInt64(copied);

		Sys.println('sum=' + Int64.toStr(sum));
		Sys.println('diff=' + Int64.toStr(diff));
		Sys.println('prod=' + Int64.toStr(prod));
		Sys.println('div=' + Int64.toStr(div));
		Sys.println('mod=' + Int64.toStr(mod));
		Sys.println('shl=' + Int64.toStr(shl));
		Sys.println('shr=' + Int64.toStr(shr));
		Sys.println('ushr=' + Int64.toStr(ushr));
		Sys.println('and=' + Int64.toStr(anded));
		Sys.println('xor=' + Int64.toStr(xored));
		Sys.println('neg=' + Int64.toStr(neg));
		Sys.println('dm=' + Int64.toStr(dm.quotient) + ',' + Int64.toStr(dm.modulus));
		Sys.println('cmp=' + cmp + ',ucmp=' + ucmp);
		Sys.println('parse=' + Int64.toStr(c));
		Sys.println('fromFloat=' + Int64.toStr(d));
		Sys.println('toInt=' + toInt);
		Sys.println('copy=' + copied.high + ',' + copied.low);
		Sys.println('flags=' + isNeg + ',' + isZero + ',' + isInt64);
	}
}
