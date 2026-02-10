import sys.Http;
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Thread;

class Main {
	static function main(): Void {
		final server = new Socket();
		server.bind(new Host("127.0.0.1"), 0);
		server.listen(1);

		final port = server.host().port;

		Thread.create(() -> {
			final client = server.accept();
			// Read until end of headers (\r\n\r\n). We don't parse; just consume.
			final req = client.input.readAll().toString();
			if (req.indexOf("\r\n\r\n") < 0) {
				client.close();
				server.close();
				return;
			}
			client.output.writeString("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok");
			client.close();
			server.close();
		});

		final h = new Http("http://127.0.0.1:" + port + "/");
		h.onData = function(d) Sys.println(d);
		h.onError = function(e) throw e;
		h.request(false);
	}
}
