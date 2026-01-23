class Foo {
    public var x:Int;

    public function new(x:Int) {
        this.x = x;
    }

    public function inc():Void {
        this.x = this.x + 1;
    }

    public function getX():Int {
        return this.x;
    }
}

