import rust.concurrent.Channel;
import rust.concurrent.Channels;
import rust.concurrent.Mutex;
import rust.concurrent.Mutexes;
import rust.concurrent.Task;
import rust.concurrent.RwLock;
import rust.concurrent.RwLocks;
import rust.concurrent.Tasks;

class Counter {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

class Main {
	static function main():Void {
		var channel:rust.HxRef<Channel<String>> = Channels.create();
		var workerChannel = channel;
		var task:rust.HxRef<Task<Int>> = Tasks.spawn(() -> {
			Channels.send(workerChannel, "ping");
			return 2;
		});

		var received = Channels.recv(channel);
		var joined = Tasks.join(task);

		var mutex:rust.HxRef<Mutex<Counter>> = Mutexes.create(new Counter(1));
		var mutexValue = Mutexes.update(mutex, counter -> {
			counter.value = counter.value + joined;
			return counter;
		});

		var lock:rust.HxRef<RwLock<Counter>> = RwLocks.create(new Counter(5));
		var before = RwLocks.read(lock);
		var after = RwLocks.update(lock, counter -> {
			counter.value = counter.value + 4;
			return counter;
		});
		var finalValue = RwLocks.read(lock);

		var empty = switch (Channels.tryRecv(channel)) {
			case None: true;
			case Some(_): false;
		};

		trace(received);
		trace(joined);
		trace(mutexValue.value);
		trace(before.value);
		trace(after.value);
		trace(finalValue.value);
		trace(empty);
	}
}
