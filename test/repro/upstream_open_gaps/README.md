# Upstream Open Gap Repros

These fixtures are generic haxe.rust pressure cases extracted from a larger
application compile. They intentionally avoid product-specific application
types, credentials, and local machine paths so each case can be lifted into an
upstream compiler/runtime test.

The current runner records expected failures for open haxe.rust beads:

- `nullable_interface_null` -> `haxe.rust-bm6`
- `path_directory` -> `haxe.rust-lj8`
- `string_last_index_of` -> `haxe.rust-7s4`

Run them from the haxe.rust repository root:

```bash
bash scripts/ci/check-upstream-open-gap-repros.sh
```

When a compiler fix lands, flip the corresponding case from expected failure
to a passing snapshot or semantic-diff fixture, then close the linked bead.
