@:rustImpl("std::marker::Unpin")
@:rustImpl("std::fmt::Display", "fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result { write!(f, \"Foo({})\", self.x) }")
class Foo {
  public var x:Int;

  public function new(x:Int) {
    this.x = x;
  }
}

class Main {
  static function main() {
    var f = new Foo(123);
    trace(f.x);
  }
}
