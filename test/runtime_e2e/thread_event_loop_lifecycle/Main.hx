import sys.thread.EventLoop.EventHandler;
import sys.thread.EventLoop.NextEventTime;
import sys.thread.Thread;

class Main {
	static final THREAD_NOT_ALIVE_ID = "HXRT-THREAD-NOT-ALIVE";
	static final PROMISE_UNDERFLOW_ID = "HXRT-EVENTLOOP-PROMISE-UNDERFLOW";

	static function describe(time:NextEventTime):String {
		return switch (time) {
			case Now: "now";
			case Never: "never";
			case AnyTime(null): "any";
			case AnyTime(_): "any_at";
			case At(_): "at";
		};
	}

	static function classifyThreadFailure(operation:Void->Void):String {
		try {
			operation();
			return "still_alive";
		} catch (message:String) {
			return message.indexOf(THREAD_NOT_ALIVE_ID) == 0 ? THREAD_NOT_ALIVE_ID : "wrong_string_error";
		}
	}

	static function waitForDead(thread:Thread):String {
		for (_ in 0...400) {
			var result = classifyThreadFailure(() -> thread.sendMessage("probe"));
			if (result != "still_alive") {
				return result;
			}
			Sys.sleep(0.005);
		}
		return "still_alive";
	}

	static function threadThrowCleanup():Void {
		var mainThread = Thread.current();
		var child = Thread.create(() -> {
			mainThread.sendMessage("child_started");
			throw "child_failure";
		});
		var started = Thread.readMessageString(true) == "child_started";
		var failure = waitForDead(child);
		Sys.println("thread_started=" + started);
		Sys.println("thread_dead=" + failure);
		Sys.println("thread_continued=true");
	}

	static function threadEventLoopThrowCleanup():Void {
		var mainThread = Thread.current();
		var child = Thread.createWithEventLoop(() -> {
			var loop = Thread.current().events;
			loop.run(() -> throw "event_failure");
			mainThread.sendMessage("event_started");
		});
		var started = Thread.readMessageString(true) == "event_started";
		var failure = waitForDead(child);
		Sys.println("event_thread_started=" + started);
		Sys.println("event_thread_dead=" + failure);
		Sys.println("event_thread_continued=true");
	}

	static function threadThrowStress():Void {
		var mainThread = Thread.current();
		var children:Array<Thread> = [];
		var childCount = 32;
		for (index in 0...childCount) {
			var childIndex = index;
			children.push(Thread.create(() -> {
				mainThread.sendMessage("stress_started_" + childIndex);
				throw "stress_failure";
			}));
		}

		var started = 0;
		for (_ in 0...childCount) {
			if (Thread.readMessageString(true) != null) {
				started++;
			}
		}

		var dead = [for (_ in 0...childCount) false];
		var deadCount = 0;
		for (_ in 0...400) {
			for (index in 0...childCount) {
				if (!dead[index]) {
					var result = classifyThreadFailure(() -> children[index].sendMessage("probe"));
					if (result == THREAD_NOT_ALIVE_ID) {
						dead[index] = true;
						deadCount++;
					}
				}
			}
			if (deadCount == childCount) {
				break;
			}
			Sys.sleep(0.005);
		}

		Sys.println("thread_stress_started=" + started);
		Sys.println("thread_stress_dead=" + deadCount);
	}

	static function repeatThrowReschedule():Void {
		var loop = Thread.current().events;
		var hits = 0;
		var handler:EventHandler = cast 0;
		handler = loop.repeat(() -> {
			hits++;
			if (hits == 1) {
				throw "repeat_failure";
			}
			loop.cancel(handler);
		}, 1);

		Sys.sleep(0.01);
		var firstCaught = false;
		try {
			loop.progress();
		} catch (message:String) {
			firstCaught = message == "repeat_failure";
		}
		Sys.sleep(0.005);
		var second = describe(loop.progress());
		var finalState = describe(loop.progress());
		Sys.println("repeat_first_caught=" + firstCaught);
		Sys.println("repeat_hits=" + hits);
		Sys.println("repeat_second=" + second);
		Sys.println("repeat_final=" + finalState);
	}

	static function repeatCancelThrowCleanup():Void {
		var loop = Thread.current().events;
		var hits = 0;
		var handler:EventHandler = cast 0;
		handler = loop.repeat(() -> {
			hits++;
			loop.cancel(handler);
			throw "repeat_cancel_failure";
		}, 1);

		Sys.sleep(0.01);
		var caught = false;
		try {
			loop.progress();
		} catch (message:String) {
			caught = message == "repeat_cancel_failure";
		}
		Sys.println("repeat_cancel_throw_caught=" + caught);
		Sys.println("repeat_cancel_throw_hits=" + hits);
		Sys.println("repeat_cancel_throw_next=" + describe(loop.progress()));
	}

	static function repeatCancelLaterDue():Void {
		var loop = Thread.current().events;
		var firstHits = 0;
		var secondHits = 0;
		var first:EventHandler = cast 0;
		var second:EventHandler = cast 0;
		first = loop.repeat(() -> {
			firstHits++;
			loop.cancel(first);
			loop.cancel(second);
		}, 1);
		second = loop.repeat(() -> secondHits++, 2);

		Sys.sleep(0.01);
		var progress = describe(loop.progress());
		Sys.println("repeat_cancel_later_first=" + firstHits);
		Sys.println("repeat_cancel_later_second=" + secondHits);
		Sys.println("repeat_cancel_later_progress=" + progress);
		Sys.println("repeat_cancel_later_next=" + describe(loop.progress()));
	}

	static function promisedUnderflow():Void {
		var loop = Thread.current().events;
		var ran = false;
		var result = "not_caught";
		try {
			loop.runPromised(() -> ran = true);
		} catch (message:String) {
			result = message.indexOf(PROMISE_UNDERFLOW_ID) == 0 ? PROMISE_UNDERFLOW_ID : "wrong_string_error";
		}
		Sys.println("promised_underflow=" + result);
		Sys.println("promised_underflow_ran=" + ran);
		Sys.println("promised_underflow_next=" + describe(loop.progress()));
		Sys.println("promised_underflow_continued=true");
	}

	static function promisedThrowBalance():Void {
		var loop = Thread.current().events;
		loop.promise();
		loop.runPromised(() -> throw "promised_failure");
		var caught = false;
		try {
			loop.progress();
		} catch (message:String) {
			caught = message == "promised_failure";
		}
		Sys.println("promised_throw_caught=" + caught);
		Sys.println("promised_throw_next=" + describe(loop.progress()));
		Sys.println("promised_throw_continued=true");
	}

	static function main():Void {
		var mode = Sys.args()[0];
		switch (mode) {
			case "thread-throw-cleanup": threadThrowCleanup();
			case "thread-event-loop-throw-cleanup": threadEventLoopThrowCleanup();
			case "thread-throw-stress": threadThrowStress();
			case "repeat-throw-reschedule": repeatThrowReschedule();
			case "repeat-cancel-throw-cleanup": repeatCancelThrowCleanup();
			case "repeat-cancel-later-due": repeatCancelLaterDue();
			case "promised-underflow": promisedUnderflow();
			case "promised-throw-balance": promisedThrowBalance();
			case _: throw "unknown mode: " + mode;
		}
	}
}
