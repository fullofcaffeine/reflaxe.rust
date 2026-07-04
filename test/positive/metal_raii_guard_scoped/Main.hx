import rust.CloneTools;
import rust.concurrent.Mutex;
import rust.concurrent.Mutexes;
import rust.concurrent.RwLock;
import rust.concurrent.RwLocks;

class Main {
	static function main():Void {
		var mutex:rust.HxRef<Mutex<Int>> = Mutexes.create(41);
		var next = Mutexes.withRef(mutex, guard -> CloneTools.cloneValue(guard) + 1);

		var lock:rust.HxRef<RwLock<String>> = RwLocks.create("hello");
		var message = RwLocks.withRead(lock, guard -> CloneTools.cloneValue(guard) + " guard");

		trace(next);
		trace(message);
	}
}
