package sys.thread;

import haxe.Exception;

/**
	Exception thrown by `sys.thread` pool implementations.

	Why
	- The pool APIs reject invalid configurations (e.g. 0 threads) and reject work submitted after
	  shutdown. These are programmer errors, and raising a specific exception makes failures easy to
	  detect and handle.

	What
	- Used by `FixedThreadPool` and `ElasticThreadPool`.

	How
	- Plain `haxe.Exception` subtype with the default constructor.
**/
class ThreadPoolException extends Exception {}

