import rust.Option;
import rust.Result;
import rust.Vec;
import rust.net.NativeUdp;
import rust.net.SocketError;
import rust.net.UdpSocket;

class Main {
	static function main() {
		switch (NativeUdp.bindLocalhostDetailed(0)) {
			case Ok(left):
				switch (NativeUdp.bindLocalhostDetailed(0)) {
					case Ok(right):
						exchange(left, right);
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
	}

	static function exchange(left:UdpSocket, right:UdpSocket) {
		switch (left.localPortDetailed()) {
			case Ok(leftPort):
				switch (right.localPortDetailed()) {
					case Ok(rightPort):
						roundTrip(left, right, leftPort, rightPort);
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
	}

	static function roundTrip(left:UdpSocket, right:UdpSocket, leftPort:Int, rightPort:Int) {
		var payload = bytes3(0, 127, 255);
		switch (left.sendBytesToLocalhostDetailed(payload, rightPort)) {
			case Ok(sent):
				if (sent != 3) {
					fail();
				}
			case Err(_):
				fail();
		}

		switch (right.recvBytesDetailed(16)) {
			case Ok(received):
				assertBytes3(received, 0, 127, 255);
			case Err(_):
				fail();
		}

		var reply = bytes3(255, 128, 1);
		switch (right.sendBytesToLocalhost(reply, leftPort)) {
			case Ok(sent):
				if (sent != 3) {
					fail();
				}
			case Err(_):
				fail();
		}

		switch (left.recvBytes(16)) {
			case Ok(received):
				assertBytes3(received, 255, 128, 1);
			case Err(_):
				fail();
		}

		var invalid = bytes3(1, 300, 2);
		switch (left.sendBytesToLocalhostDetailed(invalid, rightPort)) {
			case Ok(_):
				fail();
			case Err(error):
				inspectInvalidInput(error);
		}
	}

	static function bytes3(a:Int, b:Int, c:Int):Vec<Int> {
		var out = new Vec<Int>();
		out.push(a);
		out.push(b);
		out.push(c);
		return out;
	}

	static function assertBytes3(bytes:Vec<Int>, a:Int, b:Int, c:Int) {
		var third:Option<Int> = bytes.pop();
		switch (third) {
			case Some(value):
				if (value != c) {
					fail();
				}
			case None:
				fail();
		}
		var second:Option<Int> = bytes.pop();
		switch (second) {
			case Some(value):
				if (value != b) {
					fail();
				}
			case None:
				fail();
		}
		var first:Option<Int> = bytes.pop();
		switch (first) {
			case Some(value):
				if (value != a) {
					fail();
				}
			case None:
				fail();
		}
		switch (bytes.pop()) {
			case Some(_):
				fail();
			case None:
		}
	}

	static function inspectInvalidInput(error:SocketError) {
		if (!error.isInvalidInput() || error.isIo() || error.isUtf8()) {
			fail();
		}
		if (error.message() == "") {
			fail();
		}
	}

	static function fail() {
		trap(1);
	}

	static function trap(code:Int) {
		var zero = code - code;
		var trap = 1 % zero;
		if (trap == -1) {
			return;
		}
	}
}
