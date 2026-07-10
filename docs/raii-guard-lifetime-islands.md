# RAII Guard And Lifetime-Island Rules

Rust RAII guard types such as `MutexGuard`, `RwLockReadGuard`, file locks, socket sessions, parser
borrows, and transaction handles are useful because `Drop` ends the critical section. Haxe does not
have Rust lifetime syntax, so `reflaxe.rust` exposes those guards through scoped callbacks or hides
them inside typed Rust extern islands.

## Selection Rules

Use a scoped callback when all of these are true:

- the guard is only needed during one lexical operation;
- the callback can return an owned value, `Void`, or another non-borrowed result;
- the Rust implementation can create and drop the guard inside one helper call;
- the Haxe callback only needs `rust.Ref<T>` or `rust.MutRef<T>` access to the guarded value.

Use an extern lifetime island when any of these are true:

- the Rust API needs explicit lifetimes, HRTB, pinning, self-referential state, or const generics;
- the operation needs contained `unsafe`;
- multiple borrowed values must be related by one Rust lifetime;
- the guard would cross `await`, thread/task spawn, iterator storage, field/static storage, or a
  callback whose lifetime is not visibly lexical;
- modeling the API directly in Haxe would require raw pointers, `Dynamic`, raw `__rust__`, or a fake
  storable guard type.

Prefer value-copy/update helpers when cloning is cheap and the API does not need live borrowed access.
For example, `Mutexes.update(...)` remains useful for clone-and-replace flows, while scoped callbacks
are the explicit guard-shaped path.

## Current Scoped Lock Guards

The supported lock guard callbacks are:

```haxe
Mutexes.withRef(mutex, guard -> ownedValueFrom(guard));
Mutexes.withMut(mutex, guard -> ownedValueFromMutating(guard));
RwLocks.withRead(lock, guard -> ownedValueFrom(guard));
RwLocks.withWrite(lock, guard -> ownedValueFromMutating(guard));
```

The Rust runtime keeps the actual RAII guard inside `hxrt::concurrent`. The Haxe callback receives a
borrow token (`rust.Ref<T>` or `rust.MutRef<T>`), and the typed borrow-region analyzer rejects
returning, storing, wrapping, throwing, or otherwise escaping that token.

Accepted:

```haxe
var next = Mutexes.withRef(mutex, guard -> RefTools.toOwned(guard) + 1);
```

Migration during the pre-1.0 review: replace `CloneTools.cloneValue(guard)` with
`RefTools.toOwned(guard)`. The new name describes the public borrow-to-owned operation; the
implementation-specific `CloneTools` facade was removed before stable-major admission.

Rejected:

```haxe
var leaked = Mutexes.withRef(mutex, guard -> guard);
```

## File And Socket Guards

File, socket, TLS, and database guards should start as extern islands unless the operation is a
simple lexical borrow. The Haxe API should expose a typed facade such as:

- `withFile(path, mode, file -> ownedResult)`
- `withSocket(address, socket -> ownedResult)`
- `withTransaction(db, tx -> ownedResult)`

The implementation may use Rust lifetimes, guard/drop types, or contained `unsafe`, but the Haxe
surface should return owned results and should not expose a storable Rust guard object.

## Evidence

- `test/positive/metal_raii_guard_scoped`: scoped mutex/RwLock guards return owned values.
- `test/negative/metal_raii_guard_escape`: returning the scoped guard token is rejected before Rust
  codegen.
- `runtime/hxrt/src/concurrent.rs`: owns the concrete Rust guard lifetimes for lock helpers.
- `docs/extern-lifetime-island-cookbook.md`: shows the broader extern-island pattern for APIs that
  should not become Haxe-level lifetime signatures.
