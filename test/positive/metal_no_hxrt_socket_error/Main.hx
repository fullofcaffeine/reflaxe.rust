import rust.Result;
import rust.net.NativeTcp;
import rust.net.NativeUdp;
import rust.net.SocketError;
import rust.net.UdpSocket;

class Main {
	static function main() {
		inspectInvalidTcpPort();
		inspectInvalidUdpPort();
		inspectInvalidReceiveSize();
		inspectInvalidUtf8Datagram();
	}

	static function inspectInvalidTcpPort() {
		switch (NativeTcp.bindLocalhostDetailed(70000)) {
			case Ok(_):
				fail();
			case Err(error):
				inspectInvalidInput(error);
		}
	}

	static function inspectInvalidUdpPort() {
		switch (NativeUdp.bindLocalhostDetailed(70000)) {
			case Ok(_):
				fail();
			case Err(error):
				inspectInvalidInput(error);
		}
	}

	static function inspectInvalidReceiveSize() {
		switch (NativeUdp.bindLocalhostDetailed(0)) {
			case Ok(socket):
				switch (socket.recvUtf8Detailed(0)) {
					case Ok(_):
						fail();
					case Err(error):
						inspectInvalidInput(error);
				}
			case Err(_):
				fail();
		}
	}

	static function inspectInvalidUtf8Datagram() {
		switch (NativeUdp.bindLocalhostDetailed(0)) {
			case Ok(socket):
				sendInvalidDatagram(socket);
			case Err(_):
				fail();
		}
	}

	static function sendInvalidDatagram(socket:UdpSocket) {
		switch (socket.localPortDetailed()) {
			case Ok(port):
				switch (InvalidUdpSender.sendInvalidUtf8ToLocalhost(port)) {
					case Ok(sent):
						if (sent != 2) {
							fail();
						}
					case Err(_):
						fail();
				}
				switch (socket.recvUtf8Detailed(16)) {
					case Ok(_):
						fail();
					case Err(error):
						inspectUtf8(error);
				}
			case Err(_):
				fail();
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

	static function inspectUtf8(error:SocketError) {
		if (!error.isUtf8() || error.isInvalidInput() || error.isIo()) {
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
