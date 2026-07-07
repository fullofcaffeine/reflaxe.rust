import rust.Option;
import rust.Result;
import rust.Vec;
import rust.net.NativeTcp;
import rust.net.SocketError;
import rust.net.TcpListener;
import rust.net.TcpStream;

class Main {
	static function main() {
		switch (NativeTcp.bindLocalhostDetailed(0)) {
			case Ok(listener):
				switch (listener.localPortDetailed()) {
					case Ok(port):
						if (port <= 0) {
							fail();
						}
						run(listener, port);
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
	}

	static function run(listener:TcpListener, port:Int) {
		switch (NativeTcp.connectLocalhostDetailed(port)) {
			case Ok(client):
				switch (listener.acceptDetailed()) {
					case Ok(server):
						clientToServer(client, server);
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}

		switch (NativeTcp.connectLocalhostDetailed(port)) {
			case Ok(client):
				switch (listener.acceptDetailed()) {
					case Ok(_):
						var invalid = bytes3(1, 300, 2);
						switch (client.writeBytesAndShutdownWriteDetailed(invalid)) {
							case Ok(_):
								fail();
							case Err(error):
								inspectInvalidInput(error);
						}
					case Err(_):
						fail();
				}
			case Err(_):
				fail();
		}
	}

	static function clientToServer(client:TcpStream, server:TcpStream) {
		var payload = bytes3(0, 127, 255);
		switch (client.writeBytesAndShutdownWriteDetailed(payload)) {
			case Ok(wrote):
				if (!wrote) {
					fail();
				}
			case Err(_):
				fail();
		}

		switch (server.readBytesDetailed()) {
			case Ok(received):
				assertBytes3(received, 0, 127, 255);
			case Err(_):
				fail();
		}

		serverToClient(client, server);
	}

	static function serverToClient(client:TcpStream, server:TcpStream) {
		var reply = bytes3(255, 128, 1);
		switch (server.writeBytesAndShutdownWrite(reply)) {
			case Ok(wrote):
				if (!wrote) {
					fail();
				}
			case Err(_):
				fail();
		}

		switch (client.readBytes()) {
			case Ok(received):
				assertBytes3(received, 255, 128, 1);
			case Err(_):
				fail();
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
