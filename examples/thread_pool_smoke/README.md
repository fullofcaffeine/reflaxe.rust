# `thread_pool_smoke`

Portable fixed-thread-pool smoke for the Rust target.

## What this example proves

- `sys.thread.FixedThreadPool` accepts and runs multiple jobs.
- `Mutex` + `Lock` coordination works across worker threads.
- The pool can be shut down after all queued work completes.

## What this example does not prove

- raw thread message-queue behavior (`examples/sys_thread_smoke` covers that)
- `haxe.MainLoop` / `haxe.EntryPoint` scheduler parity
- broad scheduler fairness or performance guarantees

## Expected output

```text
ok:3
```

Use this when the question is: "Does the portable fixed thread-pool helper behave correctly on the Rust target?"
