package supportcrate.helper;

import rust.Result;
import rust.Vec;
import rust.process.CurrentProcess;

/**
	Metal-generated process entry point for support-crate source admission.

	The process accepts no command arguments. It reads one bounded request from
	stdin and writes one accepted or rejected binary frame to stdout. Any native
	I/O failure uses a nonzero process exit and produces no alternate authority.
**/
final class Main {
	static inline final EXIT_OK = 0;
	static inline final EXIT_USAGE = 64;
	static inline final EXIT_NATIVE = 70;

	static function main():Void {
		switch CurrentProcess.userArgumentCount() {
			case Ok(count) if (count == 0):
			case Ok(_): CurrentProcess.exit(EXIT_USAGE);
			case Err(_): CurrentProcess.exit(EXIT_NATIVE);
		}

		switch AdmissionProtocol.readRequest() {
			case Some(request):
				switch AdmissionEngine.admit(request) {
					case Ok(bundles): write(AdmissionProtocol.accepted(bundles));
					case Err(failure):
						write(AdmissionProtocol.rejected(failure.code, failure.declarationRef, failure.classpathRef, failure.componentIndex));
				}
			case None:
				write(AdmissionProtocol.rejected(2, -1, -1, -1));
		}
	}

	static function write(bytes:Vec<Int>):Void {
		switch CurrentProcess.writeStdout(bytes) {
			case Ok(_): CurrentProcess.exit(EXIT_OK);
			case Err(_): CurrentProcess.exit(EXIT_NATIVE);
		}
	}
}
