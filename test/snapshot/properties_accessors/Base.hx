class Base {
  public var x(default, set):Int = 0;

  public var y(get, set):Int;
  var _y:Int = 0;

  public function new() {}

  function set_x(v:Int):Int {
    // In Haxe, `default,set` setters commonly write back to the property name.
    // The backend must avoid compiling this into a recursive setter call.
    return x = v;
  }

  function get_y():Int {
    return _y;
  }

  function set_y(v:Int):Int {
    _y = v * 2;
    return _y;
  }
}
