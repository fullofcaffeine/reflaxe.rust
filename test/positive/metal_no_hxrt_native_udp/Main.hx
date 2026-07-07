import rust.Result;
import rust.net.NativeUdp;
import rust.net.UdpSocket;

class Main {
	static function main() {
		switch (NativeUdp.bindLocalhost(0)) {
			case Ok(left):
				switch (NativeUdp.bindLocalhost(0)) {
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
		switch (left.localPort()) {
			case Ok(leftPort):
				if (leftPort <= 0) {
					fail();
				}
				switch (right.localPort()) {
					case Ok(rightPort):
						if (rightPort <= 0) {
							fail();
						}
						roundTrip(left, right, leftPort, rightPort);
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
	}

	static function roundTrip(left:UdpSocket, right:UdpSocket, leftPort:Int, rightPort:Int) {
		switch (left.sendUtf8ToLocalhost("m56-left-to-right", rightPort)) {
			case Ok(sent):
				if (sent != 17) {
					fail();
				}
			case Err(_):
				fail();
		}

		switch (right.recvUtf8(128)) {
			case Ok(message):
				if (message != "m56-left-to-right") {
					fail();
				}
			case Err(_):
				fail();
		}

		switch (right.sendUtf8ToLocalhost("m56-right-to-left", leftPort)) {
			case Ok(sent):
				if (sent != 17) {
					fail();
				}
			case Err(_):
				fail();
		}

		switch (left.recvUtf8(128)) {
			case Ok(message):
				if (message != "m56-right-to-left") {
					fail();
				}
			case Err(_):
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
