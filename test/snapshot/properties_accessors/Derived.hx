class Derived extends Base {
  public function new() {
    super();
  }

  override function set_y(v:Int):Int {
    _y = (v + 1) * 2;
    return _y;
  }
}
