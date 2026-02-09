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

	What
	- Starts a TCP listener on 127.0.0.1:0, connects a client, round-trips "ping"/"pong".
	- Starts a UDP socket on 127.0.0.1:0, sends "hi" from a client and receives it.

	How
	- Uses `Socket.select([server], [], [], 2.0)` to wait for the listener to become readable
	  before calling `accept()` (avoids indefinite blocking on platforms where `accept` blocks).
**/
class Main {
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

		// Wait until the listener is readable (incoming connection).
		var ready = Socket.select([server], [], [], 2.0);
		if (ready.read.length == 0) throw "select timeout waiting for accept";

		var conn = server.accept();

		client.write("ping");
		client.output.flush();

		var got = conn.input.readString(4);
		if (got != "ping") throw "unexpected server read: " + got;

		conn.write("pong");
		conn.output.flush();

		var resp = client.input.readString(4);
		if (resp != "pong") throw "unexpected client read: " + resp;

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
		if (sent != msg.length) throw "udp send short write";

		var recvBuf = Bytes.alloc(2);
		var recvLen = recvBuf.length;
		var from = new Address();
		var n = udpServer.readFrom(recvBuf, 0, recvLen, from);
		var recv = recvBuf.getString(0, n);
		if (recv != "hi") throw "unexpected udp payload: " + recv;

		udpClient.close();
		udpServer.close();

		Sys.println("ok");
	}
}
