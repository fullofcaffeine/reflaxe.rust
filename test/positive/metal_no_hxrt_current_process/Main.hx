import rust.Result;
import rust.Vec;
import rust.process.CurrentProcess;
import rust.process.CurrentProcessError;

/**
 * Vertical contract for a runtime-free binary protocol helper.
 *
 * The process must reject arguments before it writes the greeting. With no
 * arguments, it writes one exact binary frame and waits for EOF or one input
 * chunk. This is intentionally close to a small compiler/helper process.
 */
class Main {
	static inline final EXIT_USAGE = 64;
	static inline final EXIT_INPUT_REJECTED = 65;
	static inline final EXIT_INTERNAL = 70;

	static function main():Void {
		verifyClosedErrors();

		switch CurrentProcess.userArgumentCount() {
			case Ok(count) if (count == 0):
			case Ok(_): CurrentProcess.exit(EXIT_USAGE);
			case Err(_): CurrentProcess.exit(EXIT_INTERNAL);
		}

		switch CurrentProcess.writeStdout(greeting()) {
			case Ok(_):
			case Err(_): CurrentProcess.exit(EXIT_INTERNAL);
		}

		switch CurrentProcess.readStdinChunk(4) {
			case Ok(chunk):
				if (chunk.isEmpty())
					CurrentProcess.exit(0);
				switch CurrentProcess.writeStderrUtf8("input rejected\n") {
					case Ok(_): CurrentProcess.exit(EXIT_INPUT_REJECTED);
					case Err(_): CurrentProcess.exit(EXIT_INTERNAL);
				}
			case Err(_): CurrentProcess.exit(EXIT_INTERNAL);
		}
	}

	static function verifyClosedErrors():Void {
		final invalidByte = new Vec<Int>();
		invalidByte.push(-1);
		switch CurrentProcess.writeStdout(invalidByte) {
			case Ok(_): CurrentProcess.exit(EXIT_INTERNAL);
			case Err(error): requireInvalidInput(error);
		}

		switch CurrentProcess.readStdinChunk(0) {
			case Ok(_): CurrentProcess.exit(EXIT_INTERNAL);
			case Err(error): requireInvalidInput(error);
		}
	}

	static function requireInvalidInput(error:CurrentProcessError):Void {
		if (!error.isInvalidInput() || error.isRead() || error.isWrite() || error.isFlush())
			CurrentProcess.exit(EXIT_INTERNAL);
	}

	static function greeting():Vec<Int> {
		final bytes = new Vec<Int>();
		bytes.push("C".code);
		bytes.push("S".code);
		bytes.push("T".code);
		bytes.push("R".code);
		bytes.push(1);
		bytes.push(0);
		bytes.push(1);
		bytes.push(0);
		for (_ in 0...8)
			bytes.push(0);
		return bytes;
	}
}
