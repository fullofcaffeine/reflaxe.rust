# Native Rust Helper Modules

This directory contains typed Rust-native facade backing code. It is not `hxrt`.

Use these helpers only when a `rust.*` / metal facade needs a real Rust type or resource that the
current Haxe/compiler surface cannot express cleanly without raw snippets, layout assumptions,
dynamic handles, or noisy generated Rust.

Before adding or expanding a helper:

- prefer compiler lowering for pure transformations from typed AST, literals, metadata, or existing
  Rust primitives
- classify the helper as `permanent-native-facade`, `lowering-candidate`, or
  `experimental-scaffold`
- document the owning Haxe facade and why lowering is insufficient today
- keep imports/dependencies narrow and direct
- reject `hxrt`, `Dynamic`, `Any`, type-erased registries, broad portable semantics, generic
  platform abstraction, and allocation-heavy adapters
- add generated call-site inspection, no-hxrt evidence, rustfmt/cargo evidence, and a policy fixture

See `docs/native-facade-policy.md` for the full taxonomy and inventory.
