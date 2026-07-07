import rust.Option;
import rust.Result;
import rust.Vec;
import rust.net.NativeTcp;
import rust.net.NativeUdp;
import rust.net.SocketAddr;
import rust.net.SocketError;
import rust.net.TcpListener;
import rust.net.TcpStream;
import rust.net.UdpSocket;

class Main {
	static function main() {
		inspectInvalidPort();
		inspectNegativePort();
		tcpRoundTrip();
		udpRoundTrip();
	}

	static function inspectInvalidPort() {
		switch (SocketAddr.localhostDetailed(70000)) {
			case Ok(_):
				fail();
			case Err(error):
				if (!error.isInvalidInput() || error.isIo() || error.isUtf8()) {
					fail();
				}
		}
	}

	static function inspectNegativePort() {
		switch (SocketAddr.localhostDetailed(-1)) {
			case Ok(_):
				fail();
			case Err(error):
				if (!error.isInvalidInput() || error.isIo() || error.isUtf8()) {
					fail();
				}
		}
	}

	static function tcpRoundTrip() {
		switch (SocketAddr.localhostDetailed(0)) {
			case Ok(bindAddr):
				switch (NativeTcp.bindDetailed(bindAddr)) {
					case Ok(listener):
						connectTcp(listener);
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
	}

	static function connectTcp(listener:TcpListener) {
		switch (listener.localAddrDetailed()) {
			case Ok(addr):
				if (addr.port() <= 0) {
					fail();
				}
				switch (NativeTcp.connectDetailed(addr)) {
					case Ok(client):
						acceptTcp(listener, client);
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
	}

	static function acceptTcp(listener:TcpListener, client:TcpStream) {
		switch (listener.acceptDetailed()) {
			case Ok(server):
				switch (client.writeUtf8AndShutdownWriteDetailed("m60-socket-addr")) {
					case Ok(wrote):
						if (!wrote) {
							fail();
						}
					case Err(_):
						fail();
				}
				switch (server.readToStringDetailed()) {
					case Ok(message):
						if (message != "m60-socket-addr") {
							fail();
						}
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
	}

	static function udpRoundTrip() {
		switch (SocketAddr.localhostDetailed(0)) {
			case Ok(leftAddr):
				switch (SocketAddr.localhostDetailed(0)) {
					case Ok(rightAddr):
						switch (NativeUdp.bindDetailed(leftAddr)) {
							case Ok(left):
								switch (NativeUdp.bindDetailed(rightAddr)) {
									case Ok(right):
										sendUdpBytes(left, right);
									case Err(_):
										fail();
								}
							case Err(_):
								fail();
						}
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
	}

	static function sendUdpBytes(left:UdpSocket, right:UdpSocket) {
		switch (right.localAddrDetailed()) {
			case Ok(rightAddr):
				var payload = new Vec<Int>();
				payload.push(109);
				payload.push(54);
				payload.push(48);
				switch (left.sendBytesToDetailed(payload, rightAddr)) {
					case Ok(sent):
						if (sent != 3) {
							fail();
						}
					case Err(_):
						fail();
				}
				switch (right.recvBytesDetailed(16)) {
					case Ok(received):
						assertBytes3(received, 109, 54, 48);
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
	}

	static function fail() {
		trap(1);
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

	static function trap(code:Int) {
		var zero = code - code;
		var trap = 1 % zero;
		if (trap == -1) {
			return;
		}
	}
}
