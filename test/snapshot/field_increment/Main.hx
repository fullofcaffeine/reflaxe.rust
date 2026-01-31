class C {
	public var x:Int;
	public function new(x:Int) this.x = x;
}

class Main {
	static function main():Void {
		var c = new C(10);
		trace(c.x++);
		trace(c.x);
		trace(++c.x);
		trace(c.x);
		trace(c.x--);
		trace(c.x);
		trace(--c.x);
		trace(c.x);
	}
}

