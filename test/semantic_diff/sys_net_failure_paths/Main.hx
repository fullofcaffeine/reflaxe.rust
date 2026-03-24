import sys.net.Host;
import sys.net.Socket;

class Main {
	static function main() {
		var loopback = new Host("127.0.0.1");

		var server = new Socket();
		server.bind(loopback, 0);
		server.listen(1);
		var port = server.host().port;
		var idle = Socket.select([server], [], [], 0.05);
		Sys.println('select_idle=' + idle.read.length + '/' + idle.write.length + '/' + idle.others.length);
		server.close();

		var connectFail = false;
		try {
			var client = new Socket();
			client.setTimeout(0.2);
			client.connect(loopback, port);
		} catch (_:Dynamic) {
			connectFail = true;
		}
		Sys.println('connect_fail=' + connectFail);
	}
}
