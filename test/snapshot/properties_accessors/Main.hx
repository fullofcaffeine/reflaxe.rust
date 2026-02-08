class Main {
  static function main() {
    var b = new Base();

    trace(b.x = 7);
    trace(b.x);
    trace(b.x++);
    trace(b.x);
    trace(++b.x);
    trace(b.x);

    trace(b.y = 3);
    trace(b.y);
    b.y += 2;
    trace(b.y);

    var p:Base = new Derived();
    trace(p.y = 3);
    trace(p.y);
  }
}
