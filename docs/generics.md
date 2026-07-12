# Generics (reflaxe.rust)

This document defines the **v1** generics story for reflaxe.rust: how Haxe type parameters map to Rust, and what constraints fall out of the runtime model.

## Goals

- Keep generic **type-checking** and **codegen** predictable and Rust-idiomatic.
- Preserve Haxe’s “values are generally reusable” expectations in the default portable runtime model.
- Support generic **interfaces** (traits) and generic **base-class polymorphism** (trait objects).
- Avoid forcing application code to use raw `untyped __rust__()` for basic generic patterns.

## Mapping: Haxe → Rust

### Generic classes

Haxe:
- `class Box<T> { var value:T; ... }`

Rust output shape (conceptual):
- `pub struct Box<T: Clone + Send + Sync> { value: T, ... }`
- `impl<T: Clone + Send + Sync> Box<T> { ... }`

Notes:
- By default, **class-level** type parameters are emitted as Rust generics **with `Clone + Send + Sync` bounds**.
  - This is a pragmatic consequence of the current runtime model (`HxRef<T>` / `HxDynRef<T>`) and
    Haxe’s value reuse semantics: methods often need to return values while borrowing `self`, so
    codegen typically uses `.clone()` for non-`Copy` data.
  - `Send + Sync` keeps generated Haxe reference values compatible with the thread-safe runtime
    handle model.
- You can override bounds with `@:rustGeneric(...)` on the class:
  - `@:rustGeneric(["T: Clone + Send + Sync + std::fmt::Debug"]) class Box<T> { ... }`

### Generic methods / functions

Haxe:
- `static function id<T>(x:T):T return x;`

Rust output shape (conceptual):
- `pub fn id<T>(x: T) -> T { x }`

Notes:
- For **function-level** generics, reflaxe.rust does **not** add default bounds.
- If a method signature mentions a generated class payload whose type parameter already has bounds,
  codegen propagates those bounds onto the method generic declaration. For example,
  `static function make<T>(value:T):Payload<T>` emits `fn make<T: Clone + Send + Sync>(...)`
  because `Payload<T>` itself requires those bounds.
- If codegen for a specific function requires bounds, specify them explicitly:
  - `@:rustGeneric("T: Clone") static function f<T>(x:T):T return x;`

Evidence:

- `test/snapshot/generic_function_type_params` keeps unconstrained `Option<T>` helpers bare.
- `test/snapshot/generic_helper_payload_bounds` proves helper methods returning/reading a generated
  class payload propagate the payload bounds into the Rust helper signature.

### Generic interfaces (traits)

Haxe:
- `interface IGet<T> { function get():T; }`

Rust output shape (conceptual):
- `pub trait IGet<T: Clone + Send + Sync> { fn get(&self) -> T; }`
- `type IGetObj<T> = HxDynRef<dyn IGet<T>>`

Notes:
- Trait methods use `&self`; returning `T` by value implies cloning/copying. We default
  `T: Clone + Send + Sync` for interface type params to keep the surface usable with the runtime's
  shared reference handles.

### Generic base-class polymorphism (trait objects)

When a class has subclasses, reflaxe.rust emits a companion trait `<Base>Trait` for dynamic dispatch:

Rust output shape (conceptual):
- `pub trait BaseTrait<T: Clone + Send + Sync> { ... }`
- `HxDynRef<dyn BaseTrait<T>>` is used where Haxe types a value as `Base<T>`.

### Inherited method shims

Rust does not inherit methods the way Haxe classes do. To preserve Haxe dispatch semantics,
`reflaxe.rust` synthesizes concrete inherited-method shims on subclasses when a base method has a
body and the subclass does not override it.

That means:

- concrete calls on a subclass can resolve inherited methods,
- base-trait impls for subclasses delegate to real methods rather than `todo!()` stubs,
- `super.method(...)` calls compile through per-base super thunks on the current class.

Evidence:

- `test/snapshot/inheritance_inherited_method`
- `test/snapshot/super_method_call`
- `test/semantic_diff/virtual_dispatch`

## Concrete superclass specialization

A non-generic subclass may concretely instantiate a generic base:

```haxe
class StringBox extends Box<String> {}
```

reflaxe.rust specializes inherited physical fields, constructor parameters/bodies, inherited method
signatures, accessors, and base-trait implementations before emitting the subclass. Multi-level
chains compose their arguments as well: `Leaf extends Mid<String>` plus
`Mid<T> extends Base<Array<T>>` emits `Base<Array<String>>` surfaces for `Leaf`.

This is compiler-owned typed lowering. The generated child contains direct concrete Rust types; it
does not add runtime type erasure or an `hxrt` specialization layer.

Evidence:

- `test/semantic_diff/generic_base_specialization`
- `test/snapshot/generics_inheritance` (open `Sub<T> extends Base<T>` parameters remain generic)

## Phantom type parameters (`PhantomData`)

Rust rejects unused type parameters on structs.

If a class has type parameters but none of them appear in instance fields, reflaxe.rust injects:
- `__hx_phantom: std::marker::PhantomData<T>` (or a tuple for multiple params)

This is internal codegen detail; it has no Haxe-visible API impact.

## Constructor initialization and `Default`

Rust requires every struct field to be initialized.

To avoid requiring `T: Default` for common generic patterns (e.g. `class Box<T> { var value:T; }`), reflaxe.rust performs a conservative optimization:

- If the constructor body starts with one or more assignments like:
  - `this.value = value;`
- Those leading assignments are lifted into the struct literal used during allocation.

This keeps generic classes usable without introducing unsafe initialization.

## Current limitations (v1)

- Some patterns that depend on Rust lifetimes (borrowing across scopes) must be expressed using `rust.Ref<T>` / `rust.MutRef<T>` and scope-based helpers (see `docs/metal-profile.md`).
- Generic trait-object and lifetime-heavy designs remain conservative when they require Rust lifetime
  relationships Haxe cannot express directly.
