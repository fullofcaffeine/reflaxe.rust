# Generics (reflaxe.rust)

This document defines the **v1** generics story for reflaxe.rust: how Haxe type parameters map to Rust, and what constraints fall out of the runtime model.

## Goals

- Keep generic **type-checking** and **codegen** predictable and Rust-idiomatic.
- Preserve Haxe’s “values are generally reusable” expectations in the default (portable/idiomatic) runtime model.
- Support generic **interfaces** (traits) and generic **base-class polymorphism** (trait objects).
- Avoid forcing application code to use raw `untyped __rust__()` for basic generic patterns.

## Mapping: Haxe → Rust

### Generic classes

Haxe:
- `class Box<T> { var value:T; ... }`

Rust output shape (conceptual):
- `pub struct Box<T: Clone> { value: T, ... }`
- `impl<T: Clone> Box<T> { ... }`

Notes:
- By default, **class-level** type parameters are emitted as Rust generics **with a `Clone` bound**.
  - This is a pragmatic consequence of the current runtime model (`Rc<RefCell<_>>`) and Haxe’s value reuse semantics: methods often need to return values while borrowing `self`, so codegen typically uses `.clone()` for non-`Copy` data.
- You can override bounds with `@:rustGeneric(...)` on the class:
  - `@:rustGeneric(["T: Clone + std::fmt::Debug"]) class Box<T> { ... }`

### Generic methods / functions

Haxe:
- `static function id<T>(x:T):T return x;`

Rust output shape (conceptual):
- `pub fn id<T>(x: T) -> T { x }`

Notes:
- For **function-level** generics, reflaxe.rust does **not** add default bounds.
- If codegen for a specific function requires bounds, specify them explicitly:
  - `@:rustGeneric("T: Clone") static function f<T>(x:T):T return x;`

### Generic interfaces (traits)

Haxe:
- `interface IGet<T> { function get():T; }`

Rust output shape (conceptual):
- `pub trait IGet<T: Clone> { fn get(&self) -> T; }`
- `type IGetObj<T> = Rc<dyn IGet<T>>`

Notes:
- Trait methods use `&self`; returning `T` by value implies cloning/copying. We default `T: Clone` for interface type params to keep the surface usable.

### Generic base-class polymorphism (trait objects)

When a class has subclasses, reflaxe.rust emits a companion trait `<Base>Trait` for dynamic dispatch:

Rust output shape (conceptual):
- `pub trait BaseTrait<T: Clone> { ... }`
- `Rc<dyn BaseTrait<T>>` is used where Haxe types a value as `Base<T>`.

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

- Some patterns that depend on Rust lifetimes (borrowing across scopes) must be expressed using `rust.Ref<T>` / `rust.MutRef<T>` and scope-based helpers (see `docs/rusty-profile.md`).
- “Inherited method without override” for base-class trait dispatch is still conservative: subclasses should override methods they want reachable via a base-typed value.

