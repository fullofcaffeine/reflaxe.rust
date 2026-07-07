import rust.Option;
import rust.Vec;
import rust.net.NativeTcp;
import rust.net.NativeUdp;
import rust.net.SocketAddr;
import rust.net.TcpListener;
import rust.net.TcpStream;
import rust.net.UdpSocket;

class Main {
	static function main() {
		tcpUtf8();
		udpBytes();
	}

	static function tcpUtf8() {
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
				exchangeTcp(client, server);
			case Err(_):
				fail();
		}
	}

	static function exchangeTcp(client:TcpStream, server:TcpStream) {
		switch (client.writeUtf8AndShutdownWriteDetailed("metal-native-net")) {
			case Ok(wrote):
				if (!wrote) {
					fail();
				}
			case Err(_):
				fail();
		}

		switch (server.readToStringDetailed()) {
			case Ok(message):
				if (message != "metal-native-net") {
					fail();
				}
			case Err(_):
				fail();
		}
	}

	static function udpBytes() {
		switch (SocketAddr.localhostDetailed(0)) {
			case Ok(leftAddr):
				switch (SocketAddr.localhostDetailed(0)) {
					case Ok(rightAddr):
						switch (NativeUdp.bindDetailed(leftAddr)) {
							case Ok(left):
								switch (NativeUdp.bindDetailed(rightAddr)) {
									case Ok(right):
										sendUdp(left, right);
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

	static function sendUdp(left:UdpSocket, right:UdpSocket) {
		switch (right.localAddrDetailed()) {
			case Ok(rightAddr):
				var payload = new Vec<Int>();
				payload.push(1);
				payload.push(2);
				payload.push(255);
				switch (left.sendBytesToDetailed(payload, rightAddr)) {
					case Ok(sent):
						if (sent != 3) {
							fail();
						}
					case Err(_):
						fail();
				}
				switch (right.recvBytesDetailed(16)) {
					case Ok(bytes):
						assertBytes3(bytes, 1, 2, 255);
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
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
