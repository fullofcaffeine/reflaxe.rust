# Upstream Open Gap Repros

These fixtures are generic haxe.rust pressure cases extracted from a larger
application compile. They intentionally avoid product-specific application
types, credentials, and local machine paths so each case can be lifted into an
upstream compiler/runtime test.

The current runner has no open expected-failure repros.

Run them from the haxe.rust repository root:

```bash
bash scripts/ci/check-upstream-open-gap-repros.sh
```

When a new compiler gap is found, add a minimal expected-failure case here,
then flip it to a passing snapshot or semantic-diff fixture when the fix lands.
