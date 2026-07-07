import rust.Result;
import rust.net.NativeTcp;
import rust.net.TcpListener;
import rust.net.TcpStream;

class Main {
	static function main() {
		switch (NativeTcp.bindLocalhost(0)) {
			case Ok(listener):
				roundTrip(listener);
			case Err(_):
				fail();
		}
	}

	static function roundTrip(listener:TcpListener) {
		switch (listener.localPort()) {
			case Ok(port):
				if (port <= 0) {
					fail();
				}
				connectAndExchange(listener, port);
			case Err(_):
				fail();
		}
	}

	static function connectAndExchange(listener:TcpListener, port:Int) {
		switch (NativeTcp.connectLocalhost(port)) {
			case Ok(client):
				acceptAndExchange(listener, client);
			case Err(_):
				fail();
		}
	}

	static function acceptAndExchange(listener:TcpListener, client:TcpStream) {
		switch (listener.accept()) {
			case Ok(server):
				clientToServer(client, server);
			case Err(_):
				fail();
		}
	}

	static function clientToServer(client:TcpStream, server:TcpStream) {
		switch (client.writeUtf8AndShutdownWrite("m55-client-to-server")) {
			case Ok(wrote):
				if (!wrote) {
					fail();
				}
			case Err(_):
				fail();
		}

		switch (server.readToString()) {
			case Ok(message):
				if (message != "m55-client-to-server") {
					fail();
				}
			case Err(_):
				fail();
		}

		serverToClient(client, server);
	}

	static function serverToClient(client:TcpStream, server:TcpStream) {
		switch (server.writeUtf8AndShutdownWrite("m55-server-to-client")) {
			case Ok(wrote):
				if (!wrote) {
					fail();
				}
			case Err(_):
				fail();
		}

		switch (client.readToString()) {
			case Ok(message):
				if (message != "m55-server-to-client") {
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
