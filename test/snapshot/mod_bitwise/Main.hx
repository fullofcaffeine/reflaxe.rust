class Main {
	static function main() {
		var a = 7;
		var b = 3;

		Sys.println(a % b);
		Sys.println(a & b);
		Sys.println(a | b);
		Sys.println(a ^ b);
		Sys.println(a << 2);
		Sys.println(a >> 1);
		Sys.println(a >>> 1);
		Sys.println(~a);

		var c = 1;
		c += 2;
		c %= 2;
		c |= 4;
		c &= 7;
		c ^= 3;
		c <<= 1;
		c >>= 1;
		Sys.println(c);
	}
}

