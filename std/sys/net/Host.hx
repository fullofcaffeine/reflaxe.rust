package sys.net;

/**
	`sys.net.Host` (Rust target implementation)

	Why
	- The upstream stdlib declares `sys.net.Host` as `extern`, so sys targets must provide a real
	  implementation.
	- Most `sys.net.*` APIs use `Host.ip:Int` as the canonical way to represent an IPv4 address.

	What
	- Resolves a hostname to an IPv4 address (`ip:Int`).
	- Converts the stored IP to a dotted-quad string.
	- Supports reverse lookup and retrieving the local hostname.

	How
	- Resolution is performed by the Rust runtime (`hxrt::net`) using the platform DNS resolver.
	- The `ip` integer is stored in network byte order (big-endian), like C `inet_addr`.
**/
class Host {
	/**
		The provided host string.
	**/
	public var host(default, null): String;

	/**
		The resolved IPv4 address (network order / big-endian).
	**/
	public var ip(default, null): Int;

	public function new(name: String): Void {
		host = name;
		ip = untyped __rust__("hxrt::net::host_resolve({0}.as_str())", name);
	}

	/**
		Returns the dotted-quad IP representation of this host.
	**/
	public function toString(): String {
		return untyped __rust__("hxrt::net::host_to_string({0} as i32)", ip);
	}

	/**
		Performs a reverse DNS query to resolve a name for this host.

		Note: this is best-effort; on failure it falls back to `toString()`.
	**/
	public function reverse(): String {
		return untyped __rust__("hxrt::net::host_reverse({0} as i32)", ip);
	}

	/**
		Returns the local computer host name (best-effort).
	**/
	public static function localhost(): String {
		return untyped __rust__("hxrt::net::host_local()");
	}
}
