import haxe.io.Bytes;
import sys.net.Address;
import sys.net.Host;
import sys.net.Socket;
import sys.net.UdpSocket;

/**
	Minimal loopback networking smoke test.

	Why
	- Exercises `sys.net.Host`, `sys.net.Socket` (TCP), `sys.net.UdpSocket` (UDP), and `Socket.select`
	  in a single process.
	- Uses bounded waits so CI failures are explicit timeouts instead of indefinite blocking.

	What
	- Starts a TCP listener on 127.0.0.1:0, connects a client, round-trips "ping"/"pong".
	- Starts a UDP socket on 127.0.0.1:0, sends "hi" from a client and receives it.

	How
	- Polls readability with `Socket.select` in short slices.
	- Fails with clear timeout messages when an expected network event does not arrive.
**/
class Main {
	static inline final ACCEPT_TIMEOUT_SECONDS:Float = 3.0;
	static inline final UDP_TIMEOUT_SECONDS:Float = 3.0;
	static inline final SELECT_SLICE_SECONDS:Float = 0.1;

	/**
		Waits until `socket` is readable, with a bounded timeout.

		Why
		- `accept()` and `readFrom()` can block indefinitely on CI when the environment is slow/flaky.

		What
		- Repeatedly calls `Socket.select` with short waits until the socket is readable or the deadline expires.

		How
		- Uses `Sys.time()` to compute a deadline and sleeps via `select` to avoid busy-looping.
	**/
	static function waitReadable(socket:Socket, timeoutSeconds:Float, label:String):Void {
		var deadline = Sys.time() + timeoutSeconds;

		while (true) {
			var now = Sys.time();
			if (now >= deadline)
				break;

			var remaining = deadline - now;
			var wait = remaining < SELECT_SLICE_SECONDS ? remaining : SELECT_SLICE_SECONDS;
			var ready = Socket.select([socket], [], [], wait);
			if (ready.read.length > 0)
				return;
		}

		throw 'select timeout waiting for ${label}';
	}

	static function main() {
		var loop = new Host("127.0.0.1");

		// TCP: server bind/listen on ephemeral port.
		var server = new Socket();
		server.bind(loop, 0);
		server.listen(1);
		var serverPort = server.host().port;

		// TCP: connect client.
		var client = new Socket();
		client.connect(loop, serverPort);

		waitReadable(server, ACCEPT_TIMEOUT_SECONDS, "accept");
		var conn = server.accept();

		client.write("ping");
		client.output.flush();

		var got = conn.input.readString(4);
		if (got != "ping")
			throw "unexpected server read: " + got;

		conn.write("pong");
		conn.output.flush();

		var resp = client.input.readString(4);
		if (resp != "pong")
			throw "unexpected client read: " + resp;

		conn.close();
		client.close();
		server.close();

		// UDP: server bind on ephemeral port.
		var udpServer = new UdpSocket();
		udpServer.bind(loop, 0);
		var udpPort = udpServer.host().port;

		// UDP: client bind (so the OS allocates a local port).
		var udpClient = new UdpSocket();
		udpClient.bind(loop, 0);

		var target = new Address();
		target.host = loop.ip;
		target.port = udpPort;

		var msg = Bytes.ofString("hi");
		var sent = udpClient.sendTo(msg, 0, msg.length, target);
		if (sent != msg.length)
			throw "udp send short write";

		waitReadable(udpServer, UDP_TIMEOUT_SECONDS, "udp packet");
		var recvBuf = Bytes.alloc(2);
		var recvLen = recvBuf.length;
		var from = new Address();
		var n = udpServer.readFrom(recvBuf, 0, recvLen, from);
		var recv = recvBuf.getString(0, n);
		if (recv != "hi")
			throw "unexpected udp payload: " + recv;

		udpClient.close();
		udpServer.close();

		Sys.println("ok");
	}
}
