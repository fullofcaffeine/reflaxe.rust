# `sys_thread_smoke`

Portable `sys.thread` smoke for the Rust target.

## What this example proves

- `Thread.create` runs real OS-thread work.
- `Mutex` is re-entrant in the Haxe-documented way.
- A worker can send a message back to the main thread.
- The main thread can block on `Thread.readMessageString(true)` and receive that message.

## What this example does not prove

- `haxe.MainLoop` / `haxe.EntryPoint` scheduler parity
- thread-pool helper behavior
- async/await behavior

## Expected output

```text
child_ready
```

Use this when the question is: "Do basic Rust-target threads and thread messaging work?"
