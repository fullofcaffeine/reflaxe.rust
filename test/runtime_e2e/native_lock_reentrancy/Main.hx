import rust.HxRef;
import rust.concurrent.Mutex;
import rust.concurrent.Mutexes;
import rust.concurrent.RwLock;
import rust.concurrent.RwLocks;

class Main {
	static final REENTRANCY_ERROR_ID = "HXRT-LOCK-REENTRANCY";

	static function classify(operation:Void->Void):String {
		try {
			operation();
			return "not_caught";
		} catch (message:String) {
			return message.indexOf(REENTRANCY_ERROR_ID) == 0 ? REENTRANCY_ERROR_ID : "wrong_string_error";
		}
	}

	static function report(label:String, operation:Void->Void):Void {
		Sys.println(label + "=" + classify(operation));
		Sys.println(label + "_continued=true");
	}

	static function mutexUpdate():Void {
		var mutex:HxRef<Mutex<Int>> = Mutexes.create(2);
		report("mutex_update", () -> {
			Mutexes.update(mutex, value -> value + Mutexes.get(mutex));
		});
	}

	static function mutexWithRef():Void {
		var mutex:HxRef<Mutex<Int>> = Mutexes.create(2);
		report("mutex_with_ref", () -> {
			Mutexes.withRef(mutex, _guard -> Mutexes.get(mutex));
		});
	}

	static function mutexWithMut():Void {
		var mutex:HxRef<Mutex<Int>> = Mutexes.create(2);
		report("mutex_with_mut", () -> {
			Mutexes.withMut(mutex, _guard -> Mutexes.get(mutex));
		});
	}

	static function rwLockUpdate():Void {
		var lock:HxRef<RwLock<Int>> = RwLocks.create(3);
		report("rw_lock_update", () -> {
			RwLocks.update(lock, value -> value + RwLocks.read(lock));
		});
	}

	static function rwLockReadToWrite():Void {
		var lock:HxRef<RwLock<Int>> = RwLocks.create(3);
		report("rw_lock_read_to_write", () -> {
			RwLocks.withRead(lock, _guard -> {
				RwLocks.write(lock, 9);
				return 0;
			});
		});
	}

	static function rwLockWriteToRead():Void {
		var lock:HxRef<RwLock<Int>> = RwLocks.create(3);
		report("rw_lock_write_to_read", () -> {
			RwLocks.withWrite(lock, _guard -> RwLocks.read(lock));
		});
	}

	static function mutexInnerAccess(operation:String):Void {
		var mutex:HxRef<Mutex<Int>> = Mutexes.create(2);
		var operationId = operation.split("-").join("_");
		var label = "mutex_inner_" + operationId;
		report(label, () -> {
			Mutexes.withRef(mutex, _guard -> {
				switch (operationId) {
					case "get": Mutexes.get(mutex);
					case "set": Mutexes.set(mutex, 3);
					case "replace": Mutexes.replace(mutex, 3);
					case "update": Mutexes.update(mutex, value -> value + 1);
					case "with_ref": Mutexes.withRef(mutex, _inner -> 0);
					case "with_mut": Mutexes.withMut(mutex, _inner -> 0);
					case _: throw "unknown mutex inner operation";
				}
				return 0;
			});
		});
	}

	static function rwLockInnerAccess(operation:String):Void {
		var lock:HxRef<RwLock<Int>> = RwLocks.create(3);
		var operationId = operation.split("-").join("_");
		var label = "rw_lock_inner_" + operationId;
		report(label, () -> {
			RwLocks.withRead(lock, _guard -> {
				switch (operationId) {
					case "read": RwLocks.read(lock);
					case "write": RwLocks.write(lock, 4);
					case "replace": RwLocks.replace(lock, 4);
					case "update": RwLocks.update(lock, value -> value + 1);
					case "with_read": RwLocks.withRead(lock, _inner -> 0);
					case "with_write": RwLocks.withWrite(lock, _inner -> 0);
					case _: throw "unknown RwLock inner operation";
				}
				return 0;
			});
		});
	}

	static function callbackThrowCleanup():Void {
		var mutex:HxRef<Mutex<Int>> = Mutexes.create(5);
		var mutexCaught = false;
		try {
			Mutexes.update(mutex, value -> {
				if (value == 5) {
					throw "callback_failure";
				}
				return value;
			});
		} catch (message:String) {
			mutexCaught = message == "callback_failure";
		}
		Mutexes.set(mutex, 7);

		var lock:HxRef<RwLock<Int>> = RwLocks.create(11);
		var rwCaught = false;
		try {
			RwLocks.withWrite(lock, _guard -> {
				throw "callback_failure";
				return 0;
			});
		} catch (message:String) {
			rwCaught = message == "callback_failure";
		}
		RwLocks.write(lock, 13);

		Sys.println("callback_throw_cleanup="
			+ (mutexCaught && rwCaught && Mutexes.get(mutex) == 7 && RwLocks.read(lock) == 13));
	}

	static function caughtReentryKeepsScope():Void {
		var mutex:HxRef<Mutex<Int>> = Mutexes.create(5);
		var mutexValue = Mutexes.update(mutex, value -> {
			var first = classify(() -> Mutexes.get(mutex));
			var second = classify(() -> Mutexes.set(mutex, 99));
			return first == REENTRANCY_ERROR_ID && second == REENTRANCY_ERROR_ID ? value + 1 : -1;
		});

		var lock:HxRef<RwLock<Int>> = RwLocks.create(7);
		var rwValue = RwLocks.update(lock, value -> {
			var first = classify(() -> RwLocks.read(lock));
			var second = classify(() -> RwLocks.write(lock, 99));
			return first == REENTRANCY_ERROR_ID && second == REENTRANCY_ERROR_ID ? value + 1 : -1;
		});

		Sys.println("caught_reentry_scope="
			+ (mutexValue == 6 && Mutexes.get(mutex) == 6 && rwValue == 8 && RwLocks.read(lock) == 8));
	}

	static function crossHandleOrder():Void {
		var firstMutex:HxRef<Mutex<Int>> = Mutexes.create(1);
		var secondMutex:HxRef<Mutex<Int>> = Mutexes.create(2);
		var mutexValue = Mutexes.update(firstMutex, value -> value + Mutexes.get(secondMutex));

		var firstLock:HxRef<RwLock<Int>> = RwLocks.create(3);
		var secondLock:HxRef<RwLock<Int>> = RwLocks.create(4);
		var rwValue = RwLocks.update(firstLock, value -> value + RwLocks.read(secondLock));

		Sys.println("cross_handle_mutex=" + mutexValue);
		Sys.println("cross_handle_rw_lock=" + rwValue);
	}

	static function main():Void {
		var mode = Sys.args()[0];
		if (mode.indexOf("mutex-inner-") == 0) {
			mutexInnerAccess(mode.substr("mutex-inner-".length));
			return;
		}
		if (mode.indexOf("rw-lock-inner-") == 0) {
			rwLockInnerAccess(mode.substr("rw-lock-inner-".length));
			return;
		}

		switch (mode) {
			case "mutex-update": mutexUpdate();
			case "mutex-with-ref": mutexWithRef();
			case "mutex-with-mut": mutexWithMut();
			case "rw-lock-update": rwLockUpdate();
			case "rw-lock-read-to-write": rwLockReadToWrite();
			case "rw-lock-write-to-read": rwLockWriteToRead();
			case "callback-throw-cleanup": callbackThrowCleanup();
			case "caught-reentry-keeps-scope": caughtReentryKeepsScope();
			case "cross-handle-order": crossHandleOrder();
			case _: throw "unknown native lock reentrancy mode: " + mode;
		}
	}
}
