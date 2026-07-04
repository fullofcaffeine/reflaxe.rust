# Lifetime Encoding Design (Can We Encode Lifetimes In Haxe?)

This document answers a recurring question:

> Can `reflaxe.rust` encode Rust lifetimes from Haxe code?

Short answer:

- **Yes, partially**, with scoped patterns and compiler checks.
- **No, not fully**, in the same way handwritten Rust exposes generic lifetime parameters.

This is one part of the broader `metal` goal: haxified Rust. `metal` should expose Rust-native
authority through Haxe-friendly constructs, but lifetime syntax is one of the places where Haxe
cannot simply become Rust. See [Metal haxified Rust roadmap](metal-haxified-rust-roadmap.md).

## Why This Is Hard

Rust lifetimes are part of Rust's type language. Haxe does not have:

- explicit lifetime parameters (`'a`, `'b`, ...)
- higher-ranked lifetime syntax
- a native borrow checker with lifetime inference rules equivalent to Rust

So a direct 1:1 language mapping is not available.

## What We Already Have

Today, the metal contract and Rust-first APIs already encode useful lifetime-like intent through:

- borrow token types: `rust.Ref<T>`, `rust.MutRef<T>`, `rust.Slice<T>`, `rust.Str`
- scoped helpers: `rust.Borrow.withRef/withMut`, `rust.SliceTools.with`, `rust.MutSliceTools.with`
- runtime/callback boundaries that force borrows to remain short-lived
- first-pass borrow-region guards in those scoped helper macros, which reject direct escapes before
  Rust code is emitted
- a typed borrow-region analyzer that tracks local aliases of borrow-only values and rejects
  alias returns, wrapper/object/helper-call packaging, throw payloads, field/static storage, and
  stored closures that capture aliases
- local-source mutable-region tracking that rejects overlapping scoped `withMut` /
  `MutSliceTools.with` borrows of the same value while allowing sequential scopes

This is a practical "lexical lifetime" encoding strategy.

## Current Enforced Region Checks

The current implementation treats scoped helper callbacks as borrow regions. The following helpers
run a syntax-level guard before macro expansion:

- `rust.Borrow.withRef`
- `rust.Borrow.withMut`
- `rust.SliceTools.with`
- `rust.MutSliceTools.with`
- `rust.StrTools.with`

The guard rejects direct escapes of the callback token:

- the callback returns/tails the token itself
- `return token`
- assignment of the token to another slot
- returned array/object literals that directly contain the token, including nested literal
  containers
- returned closures that capture the token

After macro expansion, the compiler also runs `BorrowRegionAnalyzer` over typed AST. That pass
tracks local aliases of `rust.Ref<T>`, `rust.MutRef<T>`, `rust.Slice<T>`, `rust.MutSlice<T>`, and
`rust.Str`, then rejects:

- `var alias = token; alias` or `return alias`
- returned wrapper/object/helper-call values such as `Some(alias)`, `{borrowed: alias}`, or
  `box(alias)` when the returned type still contains a borrow-only value
- `throw alias`, or a thrown wrapper value that still contains a borrow-only alias
- field/static storage such as `stored = alias`
- field/static storage of closures that capture an alias
- nested or sibling mutable helper scopes that borrow the same local source while an earlier
  mutable borrow is still active

Examples:

```haxe
Borrow.withRef(values, r -> r); // rejected: r would escape

Borrow.withRef(values, r -> {
  escaped = r; // rejected: assignment can outlive the region
});

var len = Borrow.withRef(values, r -> VecTools.len(r)); // accepted: returns owned Int

Borrow.withRef(values, r -> {
  var alias = r;
  return alias; // rejected: alias would escape
});

var count = Borrow.withRef(values, r -> {
  var alias = r;
  VecTools.len(alias); // accepted: owned Int derived from the alias
});

var leaked = Borrow.withRef(values, r -> {
  var alias = r;
  Some(alias); // rejected: wrapper still contains a borrow-only value
});

var wrappedLen = Borrow.withRef(values, r -> {
  var alias = r;
  Some(VecTools.len(alias)); // accepted: wrapper contains an owned Int
});

Borrow.withMut(values, first -> {
  Borrow.withMut(values, second -> {
    use(second);
  }); // rejected: second mutable borrow overlaps first
});

Borrow.withMut(values, first -> mutate(first));
Borrow.withMut(values, second -> mutate(second)); // accepted: first scope ended

var summary = Borrow.withRef(text, r -> {
  contains: StrTools.with("needle", n -> StringTools.contains(r, n))
}); // accepted: returned literal contains an owned Bool, not r itself
```

Spawned closure boundaries are also checked by `SendSyncAnalyzer`: a `Thread.create(...)` or task
spawn that captures `rust.Ref<T>`, `rust.MutRef<T>`, `rust.Slice<T>`, `rust.MutSlice<T>`, or
`rust.Str` fails under the strict Send/Sync policy before Cargo reports a generated Rust error.

These checks are intentionally not advertised as a full Haxe borrow checker. They do not yet prove
every alias path: unknown closure flows through local variables, helper calls that store/capture a
borrow through side effects, field aliases created outside the current scope, and same-source proofs
beyond local source identity remain follow-up work. The rule for users is simple: borrow tokens are
borrow-region values, not owned values.

## What Is Not Currently Possible

These are not realistically expressible as first-class Haxe signatures in v1:

- generic API shapes that expose explicit lifetime parameters to users
- complex lifetime relationships across multiple return values and trait bounds
- full parity with Rust's non-lexical lifetime reasoning

## Candidate Compiler Designs

### 1) Scoped Region API (Current baseline, low risk)

Keep the existing callback-scoped model and expand it consistently:

- enter a borrow scope
- create borrow tokens only inside that scope
- reject or warn when borrow tokens escape the scope

Pseudo-shape:

```haxe
Borrow.withRef(value, r -> {
  // r: rust.Ref<T>, valid only in this callback
  return useRef(r);
});
```

Pros:

- very compatible with current architecture
- easy to explain to users
- aligns well with Rust lexical borrow intuition
- already has macro enforcement for direct token escapes, typed enforcement for first-wave alias
  escapes, escaped wrapper/throw packaging, and local-source mutable overlap diagnostics

Cons:

- cannot express reusable generic lifetime APIs
- does not catch all alias-sensitive escapes without more typed-pass expansion

### 2) Phantom Region Types (Medium risk, medium payoff)

Introduce internal "region ids" as phantom type parameters generated by macros/compiler:

- `ScopedRef<R, T>`
- `ScopedMutRef<R, T>`
- each `R` is fresh per scope

Then require region equality at use sites to prevent cross-scope leakage.

Pros:

- stronger static constraints in Haxe typing than plain `Ref<T>`
- clearer compile-time errors for escaped borrows

Cons:

- adds significant type-system complexity to user-facing APIs
- still cannot fully model all Rust lifetime features

### 3) Typed Borrow-Region Pass In Compiler (Started, higher risk, high payoff)

Add a metal-focused semantic pass over typed AST:

- track borrow creation/usage sites
- detect obvious aliasing/escape violations early
- emit targeted diagnostics before Rust codegen
- distinguish local aliases that remain inside the region from aliases stored in fields, returned
  values, captured by unknown closures, or passed into long-lived boundaries

The implemented slice covers local alias returns, returned wrapper/object/helper values whose type
still contains a borrow-only value, throw payloads, field/static storage, field/static storage of
closures that capture aliases, and overlapping mutable helper scopes on the same local source. The
remaining expansion is unknown closure variables, helper-call side effects, field/static source
identity, and richer equivalence between source expressions.

Pros:

- better UX than relying only on downstream Rust errors
- can prevent known invalid patterns earlier
- complements the existing macro guard without exposing phantom lifetime parameters to users

Cons:

- complex to implement and maintain
- may diverge from Rust behavior if rules are approximated poorly

### 4) Extern "Lifetime Islands" (Current practical fallback)

For APIs that truly need full lifetime power:

- expose a typed Haxe facade
- implement lifetime-heavy internals in handwritten Rust extern modules

Use the [Extern and lifetime-island cookbook](extern-lifetime-island-cookbook.md) for the concrete
facade/module/test pattern.

Pros:

- full Rust expressiveness where needed
- keeps normal app code clean

Cons:

- split mental model (Haxe facade + Rust internals)

### 5) RAII Guard Scoped Callbacks

Rust guard/drop APIs should not expose storable guard objects in Haxe. Simple lock guards use scoped
callbacks such as `Mutexes.withRef/withMut` and `RwLocks.withRead/withWrite`; the Rust runtime holds
the actual guard and passes `rust.Ref<T>` / `rust.MutRef<T>` into the callback. More complex file,
socket, transaction, parser, or unsafe guard APIs stay behind typed extern islands until there is a
specific Haxe surface.

See [RAII guard and lifetime-island rules](raii-guard-lifetime-islands.md).

## Recommended Direction

For near-term compiler evolution:

1. Keep callback-scoped borrow APIs as the main user model.
2. Keep the existing macro guard for direct non-escape checks.
3. Continue expanding the typed borrow-region pass beyond current alias returns, wrapper/helper
   packaging, throw payloads, field/static storage, stored closure captures, and local-source
   mutable overlap checks to unknown closure variables and richer source-provenance checks.
4. Introduce phantom-region typing only where it clearly improves correctness without harming ergonomics.
5. Expose simple RAII guards through scoped callbacks; keep lifetime-heavy generic patterns in extern
   Rust modules behind typed Haxe APIs.
6. Treat repeated lifetime-related raw snippets in metal code as requests for a typed Haxe surface,
   metadata contract, scoped macro, or extern-island pattern.

This gives meaningful lifetime safety gains without pretending to fully replace Rust's lifetime language.

## Profile Relation

- `portable`: prefer owned/high-level APIs; lifetimes stay mostly an implementation detail.
- `metal`: opt into borrow-aware APIs and scoped lifetime-like patterns deliberately.

See also:

- [Profiles](profiles.md)
- [Metal profile](metal-profile.md)
- [Profile migration guide](rusty-profile.md)
