PRD: reflaxe.rust — a Haxe → Rust target (Haxe 4.3.7)

Note: I was able to read the repomix-output.xml you attached from the provided path. If you later want me to diff against a newer snapshot of your compiler repo, you’ll need to upload the new repomix bundle too.

1. Executive summary

Build a Reflaxe-based (Reflaxe is a compiler framework for custom Haxe targets) target that compiles Haxe 4.3.7 code to idiomatic Rust, while still supporting portable Haxe semantics + Haxe standard library usage (to the extent feasible for a new target).

This target has two faces:

Portable Haxe mode (default)
Prioritize Haxe semantics and cross-target portability. Generated Rust uses a small runtime crate (Rust-side) and carefully-chosen wrappers so that “normal” Haxe code compiles and behaves consistently.

Rust-native mode (opt-in)
Allow Haxe developers to explicitly opt into Rust idioms and ecosystem interop via a Haxe-facing API layer (macros/abstracts/externs) that maps to native Rust types and patterns.

The architecture should mirror the successful patterns in your reflaxe.elixir compiler:

CompilerBootstrap + CompilerInit macros (macro-time target gating, classpath injection, compiler registration).

GenericCompiler<AST> pipeline (compiler returns AST nodes, not strings).

Builder / Transformer / Printer separation (AST is built, transformed by passes, then printed).

Output iterator (turn compiled AST into DataAndFileInfo<StringOrBytes>, generate extra files like Cargo manifests).

TargetCodeInjection + “macro injection shim” (__rust__() exists during typing and is processed later by Reflaxe injection).

2. Goals and non-goals
Goals

G1: Haxe 4.3.7 support with a stable developer experience.

G2: Generate Rust that feels like Rust:

snake_case modules/functions, PascalCase types.

Prefer Option<T> for nullable refs, Result<T,E> for explicit error APIs (where mapped).

Prefer match, for, iterators when possible.

Output should be rustfmt-clean (optional auto-run).

G3: Portable Haxe code “just works”:

A meaningful subset of Std, Type, Reflect, haxe.ds.*, haxe.io.*, sys.* should compile and run.

Semantics should be consistent with Haxe expectations, even if it costs some performance.

G4: Rust power-user escape hatches:

__rust__ injection for raw Rust.

First-class Haxe API for Rust types/features (externs + macros + abstracts).

Cargo dependency declaration via Haxe metadata/macros that the compiler reads.

G5: Maintainable compiler code:

Avoid “string regex detection” for semantics.

Prefer typed AST analysis + passes (like your Elixir transformer registry pattern).

No static global state contamination; use a CompilationContext.

Non-goals (for initial releases)

NG1: Perfect zero-cost Rust. Some wrappers are acceptable.

NG2: Full Rust lifetime/borrow modeling as a Haxe surface feature. Haxe has no lifetime syntax; we can expose safe idioms, but not the whole borrow-checker UX.

NG3: 100% Haxe stdlib parity on day 1. We’ll define a priority ladder and ship incrementally.

NG4: Cross-compiling every Rust target triple out of the gate (wasm, embedded, etc.). Keep build outputs conventional, then expand.

3. Target users and use-cases
Personas

Portable Haxe dev: writes normal Haxe, expects stdlib + portability to JS/HL/C++.

Rust-curious Haxe dev: wants to call Option/Result, iterators, crates, but still write Haxe syntax.

Library author: wants a Haxe library that’s portable, with #if rust enhancements.

Representative use-cases

Compile a Haxe CLI tool into a Rust binary with Cargo packaging.

Write portable Haxe code (no #if rust) that runs on Rust and other targets.

In Rust mode, bind to serde, regex, tokio (eventually) via Haxe externs + Cargo metadata.

Use Rust’s match and enums idiomatically when compiling Haxe switch / enums.

4. Product requirements
4.1 Functional requirements

FR1: Compiler registration + build invocation

Support a Haxe build like:

-lib reflaxe.rust

-D rust_output=path/to/out

Provide extraParams.hxml so -lib reflaxe.rust autoloads:

--macro reflaxe.rust.CompilerBootstrap.Start()

--macro reflaxe.rust.CompilerInit.Start()

FR2: File output model

Default: FilePerModule (one .rs file per Haxe module), plus generated Rust module tree files.

Generate “extra outputs”:

Cargo.toml

src/main.rs or src/lib.rs (configurable)

src/mod.rs files for directories (or lib.rs with pub mod ...; + module folders)

runtime crate source (optional copy) or path dependency wiring

FR3: Language feature coverage (incremental)

Baseline: expressions, locals, functions, if/else, while, for, switch, arrays, strings, classes, enums.

Later: interfaces, inheritance, generics, abstracts, reflection, exceptions, sys IO, threads.

FR4: Haxe stdlib compatibility strategy

Use built-in Haxe stdlib where it compiles cleanly.

Override problematic or target-specific modules (like your Elixir Bytes and Type overrides) with Rust-safe implementations.

Prefer small overrides and a Rust runtime crate for primitives rather than rewriting everything.

FR5: Rust-native Haxe API

Provide a rust.* or haxe.rust.* package that:

Offers idiomatic Rust types (Option, Result, Vec, HashMap, etc.) as externs/abstracts.

Provides macros to ergonomically build and pattern-match those types.

Allows specifying Cargo dependencies and feature flags.

5. Architecture requirements and proposed design
5.1 Repository layout (mirrors Elixir target structure)

Haxe side (reflaxe.rust haxelib):

src/
  reflaxe/rust/
    CompilerBootstrap.hx
    CompilerInit.hx
    RustCompiler.hx
    RustOutputIterator.hx
    RustTyper.hx
    CompilationContext.hx
    macros/
      RustInjection.hx        // __rust__ macro shim
      CargoMetaRegistry.hx    // collect Cargo deps/features
      StrictModeEnforcer.hx   // optional, later
    ast/
      RustAST.hx
      RustASTBuilder.hx
      RustASTTransformer.hx
      RustASTPrinter.hx
      naming/
        RustNaming.hx
      builders/
        LiteralBuilder.hx
        BinaryOpBuilder.hx
        ControlFlowBuilder.hx
        FunctionBuilder.hx
        ClassBuilder.hx
        EnumBuilder.hx
        SwitchBuilder.hx
        LoopBuilder.hx
        FieldAccessBuilder.hx
      transformers/
        registry/
          groups/...
        ...
std/
  (overrides / additions used by this target)
extraParams.hxml
haxelib.json


Rust runtime crate (shipped with the haxelib, copied or referenced):

runtime/hxrt/
  Cargo.toml
  src/
    lib.rs
    string.rs
    array.rs
    dynamic.rs
    exception.rs
    init.rs
    reflect.rs
    ...

5.2 Compiler entrypoint and Reflaxe integration

Follow the Elixir pattern:

CompilerBootstrap.Start()

Inject classpaths early:

std/ (target-specific overrides)

optionally vendored reflaxe (only if you decide you need patches like Elixir did)

Gate injection using:

Context.defined("rust_output") OR Context.definedValue("target.name") == "rust"

CompilerInit.Start()

ReflectCompiler.Start()

Configure global metadata for idiomatic mappings:

Compiler.addGlobalMetadata("haxe.ds.Option", "@:rustIdiomatic")

Compiler.addGlobalMetadata("haxe.functional.Result", "@:rustIdiomatic")

Register compiler:

fileOutputExtension: ".rs"

outputDirDefineName: "rust_output"

fileOutputType: FilePerModule

targetCodeInjectionName: "__rust__"

ignoreExterns: true (default; later allow opt-in compilation of annotated externs)

expressionPreprocessors: [...] (see §5.6)

5.3 RustCompiler design (GenericCompiler pattern)

Mirror ElixirCompiler extends GenericCompiler<ElixirAST,...>:

class RustCompiler extends GenericCompiler<RustAST, RustAST, RustAST, RustAST, RustAST>

Responsibilities:

Compile typed Haxe modules/types/exprs into RustAST nodes.

Track module dependencies for generating Rust mod tree and init ordering.

Maintain options for portable vs native mode:

-D rust_portable (default)

-D rust_native (opt-in)

Implement compileExpression():

First: handle TargetCodeInjection.checkTargetCodeInjectionGeneric(...) for __rust__.

Then compile normal expressions via RustASTBuilder.

5.4 AST-first Rust codegen (Builder → Transformer → Printer)

Core principle: avoid generating Rust strings directly except at the very end.

RustAST shape (minimum viable)

Start with a lean Rust AST that covers:

Items: module file, use, struct, enum, impl, trait, fn, const/static, type alias.

Statements: let, expr;, return, break, continue, blocks.

Expressions: literals, paths, calls, method calls, if, match, loops, struct/enum construction, indexing, field access, closures.

Types: primitives, paths, generic args, references, tuples.

You do not need to model every Rust syntactic edge-case initially—just enough to print correct code. Add nodes as needed.

Builders (modular, like your Elixir builders)

Break compilation by feature area to keep files small and responsibilities obvious:

LiteralBuilder: constants, strings, ints, floats, null.

BinaryOpBuilder: operators and coercions (+, ==, etc.).

ControlFlowBuilder: if, while, return, throw.

LoopBuilder: for lowering (portable vs idiomatic).

SwitchBuilder: Haxe switch → Rust match or if-chain.

FunctionBuilder: functions, lambdas, captures.

ClassBuilder: structs/impls, constructors, statics.

EnumBuilder: Rust enums + constructors.

FieldAccessBuilder: field access, properties, dynamic access.

Transformer passes (registry + contextual passes)

Mirror the Elixir PassConfig pattern:

Stateless passes (AST-only):

normalize blocks

simplify nested match

clean up use ordering

Contextual passes (need CompilationContext):

variable mutability inference (let vs let mut)

underscore-prefix unused bindings

borrow-scope shrinking (if using RefCell borrows)

module path qualification and dependency closure

Keep passes small; group them in registry/groups/* and run them in a stable order.

5.5 Output iterator responsibilities (RustOutputIterator)

Analogous to ElixirOutputIterator:

Input: compiled RustAST per module/type
Output: DataAndFileInfo<StringOrBytes> items:

One .rs file per Haxe module.

Additional generated files:

Cargo.toml

src/main.rs or src/lib.rs

src/<dir>/mod.rs files to wire module tree

optionally: runtime/hxrt copied into output and referenced as a path dependency

Also:

Generate a deterministic “bootstrap entry” (main) that:

initializes runtime

initializes modules/statics (see §6.4)

calls Main.main()

Optional:

Run rustfmt on output when -D rustfmt is set (best done after file writes, in onOutputComplete()).

5.6 Preprocessors (ExpressionPreprocessor) — leverage Reflaxe

Start with a “fast boot” profile similar to Elixir:

Always-on (correctness):

remove or rewrite patterns that generate invalid Rust (e.g., nested assignment weirdness, temp var aliasing).

mark unused vars so we can _foo them in Rust to avoid warnings.

Optional full cleanup:

remove temporary variables

remove unnecessary blocks

remove constant bool ifs

remove reassigned var declarations

prevent repeat variables

Rust-specific preprocessors you’ll likely need:

Make mutation explicit: identify locals that are assigned after declaration.

Break “inline assignment chains”: Rust forbids some assignment-as-expression patterns that Haxe sometimes produces via inlining/desugaring.

6. The hard problems (and concrete proposed solutions)

This section is intentionally “implementation-shaped” so Codex xhigh doesn’t face a blank wall.

6.1 Haxe object model in Rust (classes, inheritance, interfaces)

Rust has no class inheritance; Haxe does. You need a deliberate object model.

Proposed model: “Concrete structs + trait objects for polymorphism”

For each Haxe class C generate:

pub struct C { ...fields... }

impl C { ...methods... } (concrete calls)

For each “polymorphic type” (base class or interface) generate an object-safe trait:

Example: trait IAnimal { fn speak(&self) -> HxString; fn __hx_type_id(&self) -> u32; ... }

Storage / references

Use a single “reference semantics” wrapper for all class instances in portable mode:

type HxRef<T> = std::rc::Rc<std::cell::RefCell<T>> (baseline)

To store polymorphic values:

Represent values typed as interface/base as std::rc::Rc<dyn IAnimal> where the underlying allocation is RefCell<Concrete> and the trait is implemented for RefCell<Concrete>.

This requires generating impls like:

impl IAnimal for std::cell::RefCell<Dog> { ... }

So coercion works:

let a: Rc<dyn IAnimal> = dog_rc.clone();

Field access through base/interface

Haxe allows accessing base fields through base-typed variables. Rust trait objects can’t expose fields.

Solution:

Compile all instance field reads/writes (when receiver may be polymorphic) into generated accessors on the trait:

fn get_age(&self) -> i32

fn set_age(&self, v: i32)

Optimization later:

If receiver type is statically known concrete, compile to direct field access inside borrow()/borrow_mut().

Dynamic casts and RTTI (run-time type information)

To support Std.isOfType, Type.getClass, etc:

Assign each class a stable u32 type id at compile time.

Generate __hx_type_id() methods on traits, and store metadata tables in a generated module.

6.2 Memory management and cycles

Rc is easy but leaks cycles; Haxe code can create cycles.

Plan it as a staged evolution:

Milestone baseline: Rc<RefCell<T>> everywhere, document cycle leak risk.

Follow-up milestone: swap backend to a cycle-collecting pointer:

Option A: integrate a Rust tracing GC crate and generate Trace derives.

Option B: implement a minimal mark-sweep GC in hxrt specialized for generated types.

Key architectural requirement:

Keep a single abstraction point in runtime: hxrt::ref::HxRef<T> and helpers, so you can swap implementation later with minimal compiler changes.

6.3 Exceptions (throw, try/catch) without turning everything into Result

Rust panics require Send payloads, but Haxe thrown values aren’t necessarily Send.

Proposed runtime technique: “panic with an id, payload stored in thread-local”

hxrt::exception::throw(v: Dynamic) -> !:

store v in thread_local! map keyed by an incrementing u64 id

panic_any(id_u64)

hxrt::exception::catch(f: impl FnOnce() -> R) -> Result<R, Dynamic>:

catch_unwind(f)

if panic payload is u64, fetch and remove stored value and return Err(value)

otherwise re-panic

Codegen for Haxe:

try { a } catch(e: T) { b }

lower to match hxrt::exception::catch(|| { a }) { Ok(v) => v, Err(ex) => { ...typed match... } }

This preserves unwinding semantics without invasive Result threading.

6.4 Static initialization order (Haxe semantics vs Rust reality)

Haxe has class initialization semantics; Rust has const/static constraints.

Phase 1 (simple, works for many programs):

Generate __init() per module and call all __init() from main in dependency order.

Phase 2 (closer to Haxe):

Generate per-class OnceLock<()> init:

fn __init() { INIT.get_or_init(|| { ... } ); }

Inject C::__init(); at the start of:

constructors

static method bodies

static field access sites (harder; do via accessor functions)

Dependency graph

Track dependencies during compilation (like your Elixir module registry + moduleDependencies):

Each module knows which other modules it references.

OutputIterator uses this to:

generate mod tree

compute init order

avoid missing type references

6.5 Borrowing / mutability and avoiding borrow-checker pain

If you generate lots of borrow_mut() values that overlap, Rust rejects it.

Portable-mode strategy:

Make borrows extremely short-lived:

Wrap field writes in block scopes { obj.borrow_mut().x = ...; }

For reads, clone/copy out immediately: let x = obj.borrow().x.clone();

Transformer pass:

“BorrowScopeShrinkPass” that enforces short scopes and inserts temporary locals.

Native-mode strategy (later):

Use more idiomatic &mut locals when analysis proves it safe (escape analysis + no-alias analysis).

7. The Haxe Rust API (“HxRust API”)

This is the “native Rust idioms” layer that is explicitly target-specific.

7.1 Injection API (__rust__)

Mirror Elixir’s ElixirInjection.__elixir__ macro shim.

reflaxe.rust.macros.RustInjection:

public static macro function __rust__(code: String, args: Array<Expr>): Expr

emits: macro untyped __rust__($a{[code].concat(args)})

Compiler compileExpression checks TargetCodeInjection and can either:

emit a raw Rust AST node (best)

or fallback to RustExpr::Raw(String) for initial implementation

7.2 Cargo dependency declaration from Haxe

Provide @:rustCargo metadata and/or macro API:

Example:

@:rustCargo({ name: "serde", version: "1", features: ["derive"] })
extern class Serde {}


Compiler collects these into CompilationContext.cargoDeps and OutputIterator writes them into Cargo.toml.

Support:

dependencies

features

optional deps

git/path deps (later)

7.3 Rust types as externs/abstracts

Target-specific package, recommended name: rust.* (short) plus #if rust gating.

Core externs:

rust.Option<T> → Option<T>

rust.Result<T,E> → Result<T,E>

rust.Vec<T> → Vec<T>

rust.HashMap<K,V> → std::collections::HashMap<K,V>

rust.String / rust.Str for String and &str (careful with lifetimes; default to owned String)

DevEx (developer experience) macros/abstracts:

OptionTools, ResultTools implemented in Haxe as extensions, compiled idiomatically to Rust.

Pattern-match helpers that compile to match.

7.4 Trait/derive support (incremental)

Metadata:

@:rustDerive(["Clone","Debug","PartialEq"]) on classes/enums to emit derives.

@:rustImpl("trait_path") to generate impl trait_path for Type blocks (initially allow raw injected impl bodies).

8. Milestones

Each milestone is written so implementation can proceed without big design ambiguity.

Milestone 0 — Project skeleton + compiler registration

Deliverables

haxelib.json, extraParams.hxml

CompilerBootstrap.Start() and CompilerInit.Start()

RustCompiler registered via ReflectCompiler.AddCompiler(...)

RustInjection.__rust__ macro shim

Acceptance criteria

A Haxe project with -lib reflaxe.rust -D rust_output=out triggers the compiler.

Output directory receives at least one file (src/main.rs stub or similar).

Milestone 1 — Rust AST + printer + OutputIterator “hello world”

Deliverables

RustAST minimal nodes

RustASTPrinter with deterministic formatting

RustOutputIterator that prints AST to .rs

Generate minimal Cargo project:

Cargo.toml

src/main.rs calling generated Main::main() (or equivalent)

Acceptance criteria

Compile a trivial Haxe Main.main() that does trace("hi").

cargo build succeeds.

Running the binary prints something sensible (even if trace is stubbed to println!).

Milestone 2 — Typed expression coverage (core subset)

Deliverables
Implement compileExpression coverage for:

constants: null/int/float/bool/string

locals, vars, let-binding

calls, method calls

blocks

if/else

return

basic binops: + - * / == != < <= > >= && ||

unary ops: ! -

simple field access (no inheritance yet)

Acceptance criteria

Snapshot tests that compile and rustfmt-clean output for:

arithmetic

string concatenation

if/else branching

local variables and assignments

Milestone 3 — Data model: classes, fields, constructors, methods

Deliverables

ClassBuilder that emits:

struct

impl with methods

constructor function (Haxe new)

Instance allocation strategy:

portable: Rc<RefCell<T>>

Field reads/writes using short borrow scopes

Acceptance criteria

Haxe class with fields + methods compiles and runs correctly.

No borrow-checker errors in generated Rust for simple usage patterns.

Milestone 4 — Enums + switch → match

Deliverables

EnumBuilder emits Rust enum variants (tuple variants for constructor args)

SwitchBuilder maps:

enum switch → match

int/string switch → match

fallback to if-chain when patterns don’t map cleanly

Acceptance criteria

Typical Haxe enum ADT example compiles and uses match idiomatically in Rust output.

Milestone 5 — Interfaces + inheritance (portable semantics first)

Deliverables

Generate traits for interfaces and base-class polymorphism

Implement trait for RefCell<Concrete>

Generate accessors for polymorphic field/property access

Basic RTTI: stable type ids and __hx_type_id()

Acceptance criteria

Base-typed variable calling overridden method dispatches correctly.

Interface-typed variable works.

Simple Std.isOfType works (even partial).

Milestone 6 — Exceptions and try/catch

Deliverables

hxrt::exception with thread-local payload + panic id mechanism

Codegen:

throw

try/catch lowering via catch_unwind

Acceptance criteria

A Haxe example that throws and catches values behaves as expected.

Nested try/catch works.

Milestone 7 — Haxe stdlib “Tier 1” support

Define a priority ladder:

Tier 1 (must-have for real code)

Std (stringify, parse, isOfType stub)

Type (typeof, enum helpers, getClassName minimal)

Reflect (field get/set minimal)

haxe.ds.Option, haxe.functional.Result idiomatic mapping

haxe.io.Bytes (backed by Vec<u8>)

Iterators needed for for loops

Deliverables

Minimal overrides in std/ where needed, using __rust__ for runtime ops

hxrt modules backing these APIs

Acceptance criteria

Compile and run snapshot suite of stdlib-focused examples.

Milestone 8 — sys package and IO

Deliverables

Support core sys.*:

sys.io.File, sys.io.FileInput/FileOutput, sys.FileSystem, Sys

Implement via Rust std::fs, std::io, std::env, std::process

Acceptance criteria

Read/write file example works.

Directory listing works.

Basic CLI args and exit codes work.

Milestone 9 — Rust-native API layer (crate interop + ergonomics)

Deliverables

Cargo dependency registry + Cargo.toml generation

rust.* externs + helper macros

Improved injection:

prefer AST node emission for injected fragments where possible

Acceptance criteria

Example project that:

declares serde dependency

uses injected derive(Serialize, Deserialize)

serializes a Haxe-defined struct (or a rust extern) successfully

Milestone 10 — Performance + “best of both worlds” optimizations

Deliverables

Optional -D rust_native / -D rust_idiomatic mode:

arrays to Vec<T> when semantics allow (no length writes, no sparse behavior)

reduce clones in hot paths

better loop lowering to iterators

Rustfmt integration

Compilation output determinism guarantees

Acceptance criteria

Benchmarks show measurable improvements on representative workloads.

Output stays readable and stable across runs.

9. Testing strategy (copy the Elixir discipline)
Snapshot tests (primary)

Directory-driven tests:

test/snapshot/<case>/Main.hx

test/snapshot/<case>/compile.hxml

test/snapshot/<case>/intended/.../*.rs + Cargo files

A harness compiles Haxe → Rust and diffs output.

Compile-and-run tests (secondary)

cargo test integration for a subset of snapshots that execute.

For runtime correctness: file IO tests, exception tests, enum match tests.

Compiler unit tests (tertiary)

Builder tests: “Haxe AST snippet → RustAST snapshot”

Transformer tests: “input RustAST → output RustAST”

10. Key risks and mitigations

R1: Inheritance + field access becomes unmaintainable

Mitigation: accessor-based trait design + strong separation (builder generates members; transformer fixes names; printer formats).

R2: Borrow-checker fights

Mitigation: portable mode uses RefCell with tiny scopes; add transformer pass to enforce scope boundaries.

R3: Exceptions are painful

Mitigation: thread-local payload + panic id design avoids Send issues and avoids monadic rewriting.

R4: Static init order bugs

Mitigation: start with global init; evolve to per-type OnceLock init with compiler-injected calls.

R5: Stdlib scope explosion

Mitigation: tiered stdlib plan + only override what’s necessary; push low-level ops into hxrt.

11. Recommended “default decisions” to unblock implementation

These are chosen to minimize early friction:

Default mode: rust_portable

Object references: Rc<RefCell<T>>

Polymorphism: traits implemented for RefCell<Concrete>

Exceptions: thread-local payload + panic_any(id)

Module layout: src/<pkg_path>/<module_snake>.rs + generated mod.rs

Output artifact: Cargo binary crate by default (src/main.rs)

Formatting: optional rustfmt run (-D rustfmt)

If you feed this PRD into Codex xhigh, the “make-or-break” pieces it should implement first (to avoid architecture dead-ends) are: (1) AST-first pipeline + OutputIterator, (2) a coherent object model for inheritance, and (3) the exception strategy. Everything else becomes incremental once those are solid.
