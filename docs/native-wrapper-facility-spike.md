# Native Wrapper Facility Spike

Status: M94 spike only. `@:rustNativeWrapper` is reserved and currently rejected by the compiler.
Use `@:rustExtraSrc` plus a `docs/native-facade-manifest.json` entry for shipped helpers until a
future bead lands an audited generator.

## Why

Some Rust-native facades need only a thin typed wrapper around a real Rust value. `rust.net.SocketAddr`
is the current example after M95: its pure constructors and `port()` accessor are compiler-lowered,
but the crate still needs a private-field wrapper and crate-private conversions to pass
`std::net::SocketAddr` between TCP and UDP helpers.

Handwritten helpers are acceptable under the native facade policy, but simple value wrappers should
not require open-ended Rust modules forever. A generator could make the emitted Rust shape
inspectable, deterministic, and easier to guard, provided it stays narrower than `hxrt` and does not
turn metadata into arbitrary Rust string generation.

## Supported Spike Shape

The candidate metadata is object-only and belongs on an extern class whose `@:native(...)` path names
the generated Rust type.

```haxe
@:native("crate::native_socket_addr_tools::SocketAddr")
@:rustNativeWrapper({
	module: "native_socket_addr_tools",
	name: "SocketAddr",
	inner: "std::net::SocketAddr",
	field: "addr",
	derives: ["Clone", "Copy", "Debug"],
	conversions: {
		from: "from_std",
		as: "as_std",
		visibility: "pub(crate)"
	}
})
extern class SocketAddr {}
```

The minimum accepted fields for a future generator should be:

| Field | Meaning |
| --- | --- |
| `module` | Generated Rust module file name. Must be a valid non-keyword Rust identifier. |
| `name` | Generated Rust struct name. Must match the extern type's Rust-facing name. |
| `inner` | Fully qualified Rust type held by the wrapper. |
| `field` | Private wrapper field name. Must be a valid non-keyword Rust identifier. |
| `derives` | Allowlisted derive names only. The initial allowlist should be `Clone`, `Copy`, `Debug`, `Eq`, `PartialEq`, `Ord`, `PartialOrd`, and `Hash`. |
| `conversions` | Optional crate-private conversion method names. The initial visibility should be limited to `pub(crate)` or omitted private methods. |

This shape intentionally omits method bodies, arbitrary attributes, trait impl strings, unsafe
blocks, resource lifecycle hooks, custom module imports, and platform behavior.

## Generated Rust Shape

For the SocketAddr-like value wrapper, the intended generated Rust is:

```rust
#[derive(Clone, Copy, Debug)]
pub struct SocketAddr {
    addr: std::net::SocketAddr,
}

impl SocketAddr {
    pub(crate) fn from_std(addr: std::net::SocketAddr) -> SocketAddr {
        SocketAddr { addr }
    }

    pub(crate) fn as_std(&self) -> std::net::SocketAddr {
        self.addr
    }
}
```

Generated modules must be rustfmt-clean, deterministic, and manifest-visible. They should count as
native facade artifacts for the same guardrails that apply to `std/rust/native/*.rs`: owner facade,
runtime contract, allowed imports/dependency prefixes, forbidden growth, evidence owner, and review
budget. If generated helper files are added outside `std/rust/native`, the manifest guard should be
extended before the product feature ships.

## SocketAddr Assessment

`rust.net.SocketAddr` is a future candidate for generated wrapper storage and crate-private
conversions only. Its pure behavior is no longer helper-owned:

- `SocketAddr.localhost(...)` lowers to direct `u16::try_from(...)` and loopback construction.
- `SocketAddr.localhostDetailed(...)` lowers to direct port validation plus typed socket-error
  construction.
- `SocketAddr.port()` lowers to `as_std().port()` at the generated call site.

M94 does not migrate the remaining wrapper island because the metadata contract is not product-ready
and the current handwritten helper is already narrowed by manifest and output-shape guards.

## Rejected M94 Design

M94 rejects method-forwarding metadata such as:

```haxe
@:rustNativeWrapper({
	module: "native_socket_addr_tools",
	name: "SocketAddr",
	inner: "std::net::SocketAddr",
	methods: [
		{ name: "port", rust: "self.addr.port()" }
	]
})
extern class SocketAddr {}
```

That form is too close to raw Rust snippets in metadata. It creates unresolved questions about
lifetimes, borrowing, generics, result/error conversion, platform behavior, imports, `unsafe`, and
whether a method belongs in compiler lowering, a typed facade, or a native resource helper. Future
method generation should start from typed Haxe signatures and compiler-owned Rust AST, not from
string bodies inside wrapper metadata.

## Migration Criteria

A handwritten value wrapper can move to the generator only when all of these are true:

- The helper owns a single Rust value field and no live resource lifecycle.
- There is no `Drop`, partial move, borrow-region, thread-safety, `unsafe`, or platform-sensitive
  behavior.
- Pure constructors, accessors, and validators have already been compiler-lowered where the typed AST
  gives a closed answer.
- Conversion methods are private or `pub(crate)` and are used by known typed facades.
- The generated Rust shape has focused fixture coverage and policy-harness output checks.
- `docs/native-facade-manifest.json` records the generated artifact or the manifest guard is extended
  to track generated wrapper modules separately.
- Docs record why compiler lowering alone is insufficient and why `hxrt` is not involved.

Resource facades such as process children, TCP/UDP sockets, files, TLS, database handles, locks, or
guards must not use this value-wrapper facility. They require separately audited ownership semantics.

## Test Contract

`test/negative/native_wrapper_reserved_metadata` proves that `@:rustNativeWrapper` is currently
reserved. The compiler emits a hard diagnostic at the metadata site:

```text
`@:rustNativeWrapper` is reserved for the native wrapper facility spike and is not enabled as product metadata.
```

This negative fixture is intentional. It prevents unknown metadata from being silently ignored and
keeps the spike from becoming an implied stable API before generator semantics, manifest integration,
and output-shape evidence exist.

## Second-Pass Design Review

M94 is labeled `thinking:xhigh` because native-wrapper generation affects compiler architecture and
the native-facade/runtime boundary. This written second-pass review is the closure checkpoint for the
spike.

Decision: approve the reserved-metadata plus documented-contract approach for M94; do not approve a
product generator in this bead.

Review findings:

- The proposed value-wrapper shape is narrow enough to revisit later because it only covers one
  private field, allowlisted derives, and crate-private conversions.
- Method forwarding is correctly rejected for M94 because string bodies would bypass typed lowering
  and recreate app-side raw Rust authority in metadata.
- Resource lifecycle generation is correctly out of scope. Live handles need ownership, drop, partial
  move, and platform reviews that this value-wrapper model cannot provide.
- The negative fixture is appropriate evidence for a spike because acceptance allows a rejected-design
  fixture, and the compiler now fails instead of ignoring reserved metadata.
- README and FAQ do not need public updates for M94 because no usable user-facing wrapper generator
  shipped. The public interop doc gets only a reserved-metadata pointer.
