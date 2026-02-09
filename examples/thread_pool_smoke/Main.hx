import sys.thread.FixedThreadPool;
import sys.thread.Lock;
import sys.thread.Mutex;

class Main {
	static function main() {
		final pool = new FixedThreadPool(2);
		final doneLock = new Lock();
		final mutex = new Mutex();
		final doneBox = [0];

		// Clone the shared references so each closure moves its own handle.
		final doneLock1 = doneLock;
		final mutex1 = mutex;
		final doneBox1 = doneBox;
		pool.run(() -> task(doneLock1, mutex1, doneBox1));

		final doneLock2 = doneLock;
		final mutex2 = mutex;
		final doneBox2 = doneBox;
		pool.run(() -> task(doneLock2, mutex2, doneBox2));

		final doneLock3 = doneLock;
		final mutex3 = mutex;
		final doneBox3 = doneBox;
		pool.run(() -> task(doneLock3, mutex3, doneBox3));

		doneLock.wait();
		pool.shutdown();

		Sys.println("ok:" + doneBox[0]);
	}

	static function task(doneLock: Lock, mutex: Mutex, doneBox: Array<Int>) {
		mutex.acquire();
		doneBox[0] = doneBox[0] + 1;
		final d = doneBox[0];
		mutex.release();

		if (d == 3) doneLock.release();
	}
}
