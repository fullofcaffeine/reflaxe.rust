# HxRef Lifecycle and Payload Contract

## Why this contract exists

Portable Haxe classes and several typed facades need nullable shared identity: assigning a reference
creates an alias, mutation through one alias is visible through the others, and values may cross the
documented thread-safe boundaries. Rust ownership alone does not provide those Haxe-observable
semantics.

`rust.HxRef<T>` names that requirement without making the current Rust storage strategy public API.
This page separates the behavior consumers may depend on from implementation details that the
backend must remain free to improve.

## Protected behavior

For admitted APIs that expose `rust.HxRef<T>` or an equivalent portable class reference:

- a null handle represents a missing Haxe reference;
- cloning or assigning a non-null handle preserves identity rather than deep-copying the payload;
- mutation through one alias is observable through every alias to the same value;
- releasing the final strong owner of an acyclic graph releases its payload;
- expected null access is routed through the documented Haxe exception boundary; and
- thread crossing is allowed only where the owning API and the payload's declared bounds permit it.

The current Rust implementation uses shared ownership and lock-backed interior mutability. `Arc`,
`HxCell`, `RwLock`, field layout, helper methods, generated alias paths, and the exact synchronization
primitive are not compatibility promises.

## Strong cycles are not tracing-collected

Normal generated output does not include a tracing garbage collector. A graph containing only
strong `HxRef` edges can therefore retain itself after all external owners are released. Applications
that create long-lived cyclic object graphs must provide an explicit teardown point that clears at
least one strong edge in every cycle, or choose a more Rust-shaped ownership model in a typed metal
island.

This is a deliberate qualification of the portable contract, not a memory-safety defect: the
retained graph remains valid safe Rust memory. The project will not add a tracing collector merely to
erase this qualification. A collector or weak-edge public facility requires a demonstrated admitted
workload, a measured lifecycle contract, and separate compatibility review.

## Payload and thread-boundary qualifications

`HxRef<T>` by itself is an opaque handle name; it does not assert that every possible `T` can cross
every boundary. The current compiler/runtime applies bounds where their semantics require them:

- generated portable class and interface type parameters normally require `Clone + Send + Sync`;
- values boxed into `Dynamic` require a documented `Clone + Send + Sync + 'static` payload shape;
  and
- spawned thread/task closures must not capture borrow-only values such as `rust.Ref<T>`,
  `rust.MutRef<T>`, slices, or `rust.Str`, nor values whose dynamic shape cannot be proven safe at
  that boundary.

The compiler reports the last category at the Haxe source position. The default advisory diagnostic
is `HXRS-SEND-SYNC-WARNING`; `-D rust_send_sync_strict` makes it the hard
`HXRS-SEND-SYNC-ERROR` contract. These checks apply at known crossing points. They do not ban a
typed, single-threaded native value merely because that value is not `Send` or `Sync`.

## Guard scope

Shared identity does not make access re-entrant. Compiler lowering must release read/write guards
before conflicting access or user-controlled work. Callers of scoped native lock/borrow APIs must
follow the owning facade's rules; same-handle lock-callback re-entrancy is tracked separately from
the base `HxRef` lifecycle contract.

## How the contract is tested

`npm run test:hxref-lifecycle` executes deterministic runtime tests that:

- prove cloned handles share pointer identity and mutation;
- prove an acyclic payload drops exactly once after its last owner disappears; and
- prove a two-node strong cycle remains retained until both strong edges are explicitly cleared.

The lifecycle tests use `Drop` counters and weak observers, not timing or resident-memory sampling.
The diagnostic runtime contract separately compiles warning and strict-error fixtures and verifies
their stable identifiers, severities, and triggers. Portable semantic-difference cases continue to
exercise shared anonymous-record identity and mutation against Haxe's behavior.
