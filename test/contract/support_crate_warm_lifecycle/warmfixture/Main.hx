package warmfixture;

typedef Payload = {
  #if support_crate_reserved
  @:rustSupportCrate({name: "native_page_size_support"})
  #end
  final value:Int;
}

class Main {
  static function main():Void {
    final payload:Payload = {value: 1};
    trace(payload.value);
  }
}
