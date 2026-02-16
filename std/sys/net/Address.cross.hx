package sys.net;

/**
	An address represents a port on a given host ip.

	Why
	- `sys.net.UdpSocket` APIs send/receive packets to/from an `{host,port}` pair.
	- This type is part of Haxe's std API surface, but the upstream file is not emitted by this
	  backend (only repo-local `std/` overrides are emitted), so we provide it here.

	What
	- Stores `host:Int` (IPv4, network byte order) and `port:Int`.
	- Supports comparison and cloning utilities used by some std/adaptor code.

	How
	- `getHost()` constructs a `sys.net.Host` without DNS by directly initializing `Host.ip`.
**/
class Address {
	public var host:Int;
	public var port:Int;

	public function new() {
		host = 0;
		port = 0;
	}

	public function getHost():Host {
		var h = new Host("127.0.0.1");
		untyped h.ip = host;
		return h;
	}

	public function compare(a:Address):Int {
		var dh = a.host - host;
		if (dh != 0)
			return dh;
		var dp = a.port - port;
		if (dp != 0)
			return dp;
		return 0;
	}

	public function clone():Address {
		var c = new Address();
		c.host = host;
		c.port = port;
		return c;
	}
}
