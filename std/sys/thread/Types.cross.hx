package sys.thread;

/**
	`sys.thread` boundary value aliases (Rust target override)

	Why
	- Upstream `sys.thread.Thread` API uses untyped message payloads for cross-thread queues.
	- We keep this contract for compatibility while making boundary points explicit.

	What
	- `ThreadMessage`: payload type used by `Thread.sendMessage` and `Thread.readMessage`.

	How
	- This alias maps to `Dynamic` at the upstream API boundary.
	- Callers should decode to concrete types immediately after reading messages.
**/
typedef ThreadMessage = Dynamic;
