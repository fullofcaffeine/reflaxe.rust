class Main {
    static function main() {
        var o = { x: 1, s: "hi" };
        trace(o.x);
        trace(o.s);

        var o2 = o;
        o2.x = 2;
        trace(o.x);

        o.x += 3;
        trace(o.x);
        trace(o.x++);
        trace(o.x);
        o.x--;
        trace(o.x);

        o.s = o.s + "!";
        trace(o.s);
    }
}
