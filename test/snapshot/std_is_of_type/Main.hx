class Main {
    static function main() {
        var a:Animal = new Dog();
        trace(Std.isOfType(a, Animal));
        trace(Std.isOfType(a, Dog));
    }
}

