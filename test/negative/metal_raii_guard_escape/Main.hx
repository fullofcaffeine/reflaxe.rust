import rust.Ref;
import rust.concurrent.Mutex;
import rust.concurrent.Mutexes;

class Main {
	static function main():Void {
		var mutex:rust.HxRef<Mutex<Int>> = Mutexes.create(1);
		var leaked:Ref<Int> = Mutexes.withRef(mutex, guard -> guard);
		Sys.println(Std.string(leaked));
	}
}
