import sys.thread.ElasticThreadPool;
import sys.thread.Lock;
import sys.thread.Mutex;

class Main {
	static function main() {
		var pool = new ElasticThreadPool(2, 0.1);
		var done = new Lock();
		var mutex = new Mutex();
		var state = [0];

		for (_ in 0...4) {
			var done1 = done;
			var mutex1 = mutex;
			var state1 = state;
			pool.run(() -> {
				mutex1.acquire();
				state1[0] = state1[0] + 1;
				var count = state1[0];
				mutex1.release();
				if (count == 4)
					done1.release();
			});
		}

		done.wait();
		Sys.sleep(0.25);
		Sys.println("done=" + state[0] + ";threads=" + pool.threadsCount);
		pool.shutdown();
	}
}
