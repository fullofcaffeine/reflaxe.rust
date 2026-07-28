# Rust representation decision model

## Why

The compiler has to preserve Haxe identity, alias-visible mutation, nullability, and reuse while
still emitting ordinary Rust ownership wherever the source contract allows it. Those answers must
not drift between lowering, clone insertion, runtime selection, no-hxrt checks, reports, and
thread/task diagnostics.

## What

`rust-representation-policy.json` owns the closed serialized vocabulary. The compiler normalizes
typed Haxe facts into a validated decision containing the Rust storage shape, ownership and reuse
policy, explicit null encoding, semantic runtime reasons, contextual bounds, and an exact
source-private Haxe byte span.

Production lowering now derives the established scalar, enum, class, trait-object, borrow, native,
dynamic, string, array, anonymous-object, function, iterator, and nullable storage choices from this
decision. A representation-changing boundary is decided from both sides of the crossing: the value's
actual type and the destination's expected type. This is how a plain `Int`, enum, or class argument
passed to `Dynamic` gets the same Dynamic decision in early analysis and later Rust boxing. Call and
constructor arguments, local initializers, assignments, returns, casts, and control-expression
results all use that expected-type-aware path. Clone/reuse insertion, the runtime requirement report,
and the no-runtime checks consume the same answer.

For every user value that must enter `Dynamic`, the early scan saves the exact conversion action.
The action records both the complete source boundary and the smaller expression that emits the Rust
box. For example, one `if` argument has one user-facing report row, while its two concrete branches
have two lowering actions. Each branch action points back to the complete `if` range and must be used
once. The action also records a compact check of the real source type, the owned value type, and
whether lowering must use the value directly, copy through `rust.Ref<T>`, or clone through
`rust.Ref<T>`. Later lowering rebuilds that small type check and consumes the matching saved action;
it does not run the representation planner again. A malformed, missing, duplicated, or unused action
is an internal compiler error. The source description is opaque: only the typed analyzer can create
it from a real Haxe type, so callers cannot combine a `rust.Ref<String>` spelling with an unrelated
scalar/Copy classification. The saved action and its decision must also name the same exact source
location. Framework-generated conversions use a separate, explicitly labeled path so they cannot
silently hide a missed user conversion.

That framework path remains narrow for open generic values. Target std helpers such as
`DynamicAccessKeyValueIterator<T>` are not application code, so their bodies are intentionally absent
from the application saved-action snapshot. They may box their own direct `T` only when the current
framework class's structural Rust declaration already promises `Clone + Send + Sync + 'static`, the
bounds required by `Dynamic::from`. The compiler records this as a generated action. It does not apply
to application source, borrowed values, nested open types, or an under-bounded generic parameter.

Some Haxe expressions are intentionally emitted more than once. A default value is inserted at each
omitted call, a read-only static value may be inserted at each read, and a base constructor body may
also be inserted into a derived constructor. Early analysis registers a declaration expression only
after it finds a real typed use, so an unused default or read-only static declaration creates no saved
action or runtime report row. One shared typed helper names the declaration family—constructor body,
method default, constructor default, or read-only static—from its real owner. The saved action retains
that family, and every emitted copy presents the same family plus an explicit generated-site identity.
The first emitted site counts as the action's one normal use; each additional distinct site records a
replay of that same immutable decision. A caller in another module therefore still finds the action
saved under the declaration's source module, while a wrong family or a second use at the same generated
site fails. This keeps ordinary source expressions on the strict one-action/one-use rule without
pretending that a source byte range identifies every generated copy.

Connecting lowering to the saved decision intentionally corrected several generated-Rust shapes. A
one-use value entering `Dynamic` no longer receives an unnecessary clone. Class, enum, array, and
anonymous-object values use the constructor and type identity selected for their real storage shape.
`Null<T>` now converts `Some(value)` through the inner value's Dynamic conversion and converts `None`
to Dynamic null, instead of storing the Rust `Option` as an unrelated payload. A `rust.Ref<T>` crossing
materializes an owned inner value by copying or cloning `T`; the short-lived borrow itself never enters
the Dynamic container. These are reviewed correctness and output-quality changes, not byte-neutral
plumbing. Exact snapshots and focused Rust/runtime tests cover the changed forms.

Anonymous-object fields no longer ask the runtime to discover a conversion through the generic
`Anon::set<T>` helper. Generated Rust first performs the saved conversion, then calls `set_dyn` with
the finished `Dynamic` value. For a concretely declared field, the conversion preserves the field's real storage carrier—an
optional `Bool`, for example, is stored as `Option<bool>` rather than as a bare `bool`—because typed
reads retrieve that same Rust type. A field declared as `Dynamic` deliberately does not preserve the
source carrier: `None` follows ordinary Haxe null conversion and becomes Dynamic null. Typed field
reads still use `get<T>`; a field declared `Dynamic` uses `get_dyn`. Anonymous-object literals, normal
field assignments, and constant-name `Reflect.setField` therefore follow the same checked route as
parameters, returns, and ordinary fields.

One combination is rejected deliberately: a concretely typed anonymous field may not be declared
`rust.Ref<T>` or `Null<rust.Ref<T>>`. The runtime object owns values and reads them back by their exact
stored Rust type. Saving owned `T` would not match a later typed read of `&T`, while saving the
short-lived `&T` would let the borrow escape its callback. The compiler validates the complete
anonymous-record declaration when a record value is created or converted to `Dynamic`, including
`@:optional` fields omitted from a literal. This prevents runtime-name reflection—or a later write
through a `Dynamic` alias—from hiding the field declaration before mutation. Literal creation, direct
assignment, and constant-name `Reflect.setField` still report the exact stored Haxe value. When no
field value exists yet, the error points to the anonymous value whose declared shape is unsupported.
Both forms ask the author to store an owned value instead. Supporting such a field later requires an
explicit guarded-read lifetime contract; it cannot be implemented safely by changing only the written
type.

`Null<rust.Ref<T>>` emits `Option<&T>`, because a bare Rust borrow cannot represent Haxe `null`.
Nullable mutable borrows are never cloned—`Option<&mut T>` cannot be cloned. A local mutable option is
opened through `&mut` and yields a real reborrow. When an `if`, `switch`, or block chooses between
nullable mutable borrows, lowering reborrows at the result leaves so later valid uses do not move the
original option. A shared typed-Haxe control-flow helper recognizes exhaustive Bool and enum switches,
including switches without a default, so early analysis and mutable-borrow lowering agree about which
branches are complete and which following expressions are unreachable. A branch that is proven to
stop—such as `throw`—is preserved as-is; only reachable local-value branches are rewritten as
reborrows. This means a throwing arm does not force another arm to move its original `Option<&mut T>`.

Typed collection follows representation-bearing container arguments, function signatures,
anonymous fields, typedef targets, and emitted enum-constructor payloads. It deliberately skips
method/control scaffolding that does not materialize a value, so a nested `rust.Vec<Dynamic>` fails
no-hxrt without inventing requirements from compiler-only function types.

The compiler captures that collection and the no-hxrt operation scan at Haxe's completed typed-AST
boundary, before Reflaxe moves method bodies into per-class lowering data. This keeps expression-only
saved representation decisions as well as `throw`, reflection, and platform calls. Haxe may deliver
that boundary through multiple incremental callbacks, so modules are accumulated by Reflaxe's
collision-safe declaration identity and consumed once in a deterministic order. A display path is not
used as a key because a primary type such as `NotWidget` and a secondary `Widget` can otherwise
collapse to the same suffix-derived path. Direct call and constructor arguments remain value positions
even when written as `if` or `switch` expressions; their resulting type is recorded without treating
surrounding method-body control wrappers as stored values. An immediately invoked enum constructor is
call scaffolding, while a constructor stored in a variable remains a real function value.
Representation and no-runtime analysis share one call-target helper: metadata, parentheses, and a
cast between identical function types are transparent only for the immediately invoked target.
Consequently cast-wrapped `Sys`, `Type`, and `Reflect` calls keep their exact early error location,
while a type-changing cast or stored function remains a real value.

All complete source-only analyzers obtain executable class content from one helper that returns the
constructor, ordinary instance fields, and static fields. Haxe stores `ClassType.constructor`
separately, so this shared list prevents a constructor-only borrow escape, throw, reflection call, or
platform call from disappearing merely because one analyzer copied only the two ordinary field lists.

Haxe compiler positions are source-string offsets rather than the UTF-8 byte offsets promised by the
reports. The shared source-position adapter converts them against the exact source content before a
decision or operation is serialized, and converts byte ranges back before asking Haxe to place a
diagnostic. Its private real-file and line/column maps are reset once before the first completed typed
capture and remain available until final diagnostics. This preserves exact external-classpath
locations for compound `throw` and `try/catch` ranges without serializing a machine-local absolute
path. The no-hxrt check gathers information at two different times: exact source expressions are
saved early, while broader module usage becomes available later. The compiler always combines both
sets before reporting an error; finding one blocker never hides an independent reason.

## Why this is a small lowering plan, not a second full AST

**Architecture status:** accepted for the current compiler. This is a structural Rust-tree design
with small saved plans for the few choices that Rust syntax must not rediscover.

An intermediate representation, often shortened to “IR,” is a compiler-owned description placed
between the source-language tree and the target-language tree. This compiler intentionally uses a
small version of that idea: the representation plan saves decisions that must be consistent before
`RustAST` is constructed. It does not copy every Haxe expression into another complete tree.

The intended pipeline is:

```text
typed Haxe AST
    -> validated representation and boundary decisions
    -> structural RustAST
    -> Rust transformation passes
    -> printer
```

The saved decisions own facts that Rust syntax should not have to guess later:

- the selected Rust storage shape;
- whether reuse copies, moves, clones, borrows, or reborrows;
- how null is represented;
- conversions caused by an expected parameter, assignment, or return type;
- required runtime support and crossing-specific Rust bounds;
- the exact Haxe source location used in reports and diagnostics.

Adding another saved decision or temporary compiler marker requires a concrete contract:

- name the source fact that would otherwise be lost before Rust construction;
- use a closed typed choice and store only what lowering cannot safely work out later;
- name one producer and one lowering step that consumes it;
- define when it is legal, then reject malformed, duplicate, missing, or unused decisions;
- report unsupported source at its exact Haxe location instead of silently choosing a weaker form;
- prove the generated Rust shape and runtime behavior with a focused test; and
- leave the printer responsible only for formatting the already chosen Rust structure.

Checks that can reject invalid typed Haxe without looking at Rust structure run before the builder.
For example, returning a scoped `rust.Ref<T>` or `rust.Slice<T>` is reported at that Haxe return or
alias before any later Dynamic conversion is considered. This keeps the useful source error from
being replaced by an unrelated internal lowering failure.

The same early boundary reports a borrowed value that cannot become owned Dynamic storage. Known Copy
values are copied and known concrete Clone values are cloned behind `rust.Ref<T>`. A generic inner type
without a proven bound, or a native resource such as a socket that has no admitted clone operation, is
rejected at the exact Haxe call or storage expression. The compiler never attempts to put the temporary
Rust reference itself into the runtime container.

The early scan includes ordinary instance/static fields and methods plus each class constructor.
Haxe exposes a constructor separately from the normal field arrays; omitting it would let a conversion
inside `new(...)` reach lowering without the saved action required by the rest of this contract.

If several independent builders repeatedly need the same broader control-flow, cleanup, place, or
ownership model, that is new evidence for reconsidering a larger layer. A preference for symmetry,
an increasing pass count, or the existence of a fuller IR in another compiler is not enough.

A complete function IR like the `HxcIR` design in the sibling `haxe.c` project additionally models
blocks of ordered instructions, the jumps between them, variables that can be assigned to, each
variable's initialization state, where execution goes after a failure, and the cleanup that runs on
each exit. That model is necessary for C because C syntax cannot safely preserve or verify many of
those choices on its own. Rust already provides structured blocks and matches, typed enums, explicit
moves and borrows, automatic cleanup, and a compiler that checks ownership and lifetimes. Duplicating
all of that in another full tree would add conversion code, validation work, another set of source
locations to keep in sync, and new failure modes without current evidence that the extra layer would
solve more than the bounded plan.

The C design is still useful prior art. This compiler should retain its clearest ideas: distinguish a
value from a variable or field that can be assigned to, make conversions and reuse choices explicit,
validate decisions before target syntax is emitted, and keep exact source locations attached. It
should not copy the full block, instruction, jump, and cleanup model merely to make the two compilers
look alike internally.

This decision can be revisited, but only when concrete compiler fixtures show that the current design
cannot express a required behavior reliably. Strong reasons would include:

- whole-function ownership or last-use analysis that cannot be decided before Rust syntax emission;
- async, generator, or exception lowering that needs an explicit state and cleanup graph;
- multiple production passes independently rebuilding the same branch, loop, or ownership facts from
  emitted Rust nodes;
- correct output depending on fragile pattern matching against Rust syntax generated earlier.

If one of those cases appears, begin with a narrow per-function experiment and compare its complexity,
generated Rust, diagnostics, and tests with the existing plan. Do not begin with a compiler-wide
rewrite. The upcoming boundary-bound and closure work should first extend the current plan; any limit
it exposes must be recorded with a failing fixture before expanding the architecture.

Two smaller architecture improvements remain useful without changing this decision: one exhaustive
definition of every immediate `RustAST` child, and modest pass results/final checks as the pass list
grows. They protect new nodes from becoming accidental leaves and make a failed transformation easier
to locate. They are separate, output-inert migrations and should not be bundled into a representation
or Dynamic-lowering repair.

## How

Run `node scripts/ci/rust-representation-policy.js --write` after an intentional vocabulary change.
The generator updates the Haxe enum blocks, the component JSON Schema, and the reference table below.
CI and pre-commit use `--check` and compare every generated consumer byte-for-byte.

Runtime-reason entries also declare their versioned consumers. The published `runtime_plan.json`
v4 vocabulary remains immutable, while the new representation-decision v1 component may model
additional reasons before a future runtime-report version deliberately admits them.

The v4 report therefore includes the representation reasons it already admits and records their
exact typed-source spans under its existing `module` source-kind spelling. The complete decision-v1
vocabulary, including function-value and iterator reasons, remains available to the no-hxrt
eligibility analysis. A future report version may expose those additional reason IDs and a dedicated
typed-AST source kind through an explicit schema migration. Until then, function and iterator
carriers still contribute their admitted identity/mutation reasons, so v4's fallback summary never
mistakes a runtime-backed value for a no-runtime program.

<!-- BEGIN GENERATED RUST REPRESENTATION VOCABULARY -->

| Vocabulary | ID | Meaning |
| --- | --- | --- |
| `sourceValueKinds` | `scalar` | a primitive scalar with Rust Copy semantics |
| `sourceValueKinds` | `enum_value` | a reusable Haxe enum value |
| `sourceValueKinds` | `class_reference` | a concrete Haxe class reference with stable identity and shared mutation |
| `sourceValueKinds` | `polymorphic_reference` | an interface or polymorphic class reference represented through a trait object |
| `sourceValueKinds` | `borrowed_ref` | an immutable rust.Ref borrow token |
| `sourceValueKinds` | `borrowed_mut_ref` | a mutable rust.MutRef borrow token |
| `sourceValueKinds` | `borrowed_str` | a borrowed rust.Str view |
| `sourceValueKinds` | `borrowed_slice` | an immutable rust.Slice view |
| `sourceValueKinds` | `borrowed_mut_slice` | a mutable rust.MutSlice view |
| `sourceValueKinds` | `native_owned` | an explicitly Rust-native owned value |
| `sourceValueKinds` | `native_handle` | an explicitly Rust-native resource or RAII handle |
| `sourceValueKinds` | `dynamic` | a Haxe Dynamic-compatible payload |
| `sourceValueKinds` | `string` | a Haxe String using the ordinary owned Rust string contract |
| `sourceValueKinds` | `nullable_string_compat` | a Haxe String using the runtime-backed nullable compatibility contract |
| `sourceValueKinds` | `array` | a Haxe Array with shared identity and mutation |
| `sourceValueKinds` | `anonymous_object` | a runtime-shaped anonymous Haxe object |
| `sourceValueKinds` | `function_value` | a reusable Haxe function value |
| `sourceValueKinds` | `iterator` | the Haxe method-shaped iterator protocol |
| `sourceValueKinds` | `portable_facade` | a portable facade with an admitted native Rust representation |
| `sourceValueKinds` | `core_handle` | a compiler-known Class or Enum numeric handle |
| `sourceValueKinds` | `bytes_reference` | a shared haxe.io.Bytes reference |
| `identityFacts` | `none` | the value has no observable reference identity |
| `identityFacts` | `stable` | aliases must observe the same stable reference identity |
| `mutationFacts` | `immutable` | the source value is immutable |
| `mutationFacts` | `owned` | mutation belongs to one owned Rust value |
| `mutationFacts` | `exclusive_borrow` | mutation is admitted only through one lexical mutable borrow |
| `mutationFacts` | `shared` | mutation must remain visible through aliases |
| `escapeFacts` | `local` | the value is confined to its admitted lexical region |
| `escapeFacts` | `may_escape` | the value may be returned, stored, captured, or otherwise escape |
| `surfaceFacts` | `portable_haxe` | ordinary portable Haxe semantics |
| `surfaceFacts` | `portable_facade` | an explicitly admitted portable facade |
| `surfaceFacts` | `rust_native` | an explicit rust.* or typed native surface |
| `nullabilityFacts` | `non_nullable` | null is outside the source contract |
| `nullabilityFacts` | `nullable` | the representation must preserve a null value |
| `boundaryKinds` | `local` | ordinary single-thread local use |
| `boundaryKinds` | `thread` | an OS-thread spawn boundary |
| `boundaryKinds` | `task` | an asynchronous task spawn boundary |
| `boundaryKinds` | `dynamic` | boxing into the runtime Dynamic payload |
| `boundaryKinds` | `static_storage` | shared static storage with process lifetime |
| `representationKinds` | `copy_value` | an ordinary Rust Copy value |
| `representationKinds` | `owned_value` | an ordinary owned Rust value |
| `representationKinds` | `shared_identity` | a nullable HxRef-style shared identity handle |
| `representationKinds` | `shared_trait_object` | a shared trait-object identity handle |
| `representationKinds` | `borrowed_token` | a lexical Rust borrow or borrowed view |
| `representationKinds` | `native_handle` | an owned Rust-native resource or RAII handle |
| `representationKinds` | `dynamic_payload` | the hxrt Dynamic carrier |
| `representationKinds` | `runtime_string` | the nullable Haxe-compatible runtime string carrier |
| `representationKinds` | `runtime_array` | the Haxe-compatible shared runtime array carrier |
| `representationKinds` | `runtime_anonymous_object` | the shared runtime anonymous-object carrier |
| `representationKinds` | `shared_function` | the shared Haxe function-value carrier |
| `representationKinds` | `runtime_iterator` | the Haxe iterator adapter carrier |
| `nullEncodings` | `not_admitted` | the typed source value does not admit null |
| `nullEncodings` | `intrinsic` | the selected carrier owns its null sentinel |
| `nullEncodings` | `outer_option` | lowering wraps the selected base representation in Option |
| `ownershipPolicies` | `copy` | reads copy the value |
| `ownershipPolicies` | `move` | ordinary Rust moves own the value |
| `ownershipPolicies` | `shared` | a shared handle preserves aliases and identity |
| `ownershipPolicies` | `borrowed` | the value is a lexical non-owning token |
| `reusePolicies` | `copy` | reuse is free because the value is Copy |
| `reusePolicies` | `move_once` | the value moves and cannot be implicitly reused |
| `reusePolicies` | `clone_when_needed` | lowering clones only when later source reuse requires it |
| `reusePolicies` | `borrow` | reuse remains inside the admitted borrow region |
| `representationReasons` | `haxe_scalar_value` | the Haxe scalar maps directly to a Rust Copy value |
| `representationReasons` | `haxe_enum_value` | the Haxe enum maps to an owned reusable Rust enum |
| `representationReasons` | `haxe_class_identity` | class aliases require shared identity and mutation |
| `representationReasons` | `haxe_polymorphic_identity` | interface or subclass dispatch requires a shared trait object |
| `representationReasons` | `rust_borrow_surface` | an explicit rust.* borrow surface admits a lexical Rust reference |
| `representationReasons` | `rust_owned_surface` | an explicit rust.* surface admits an owned Rust value |
| `representationReasons` | `rust_native_handle` | an explicit native facade owns a Rust resource or RAII handle |
| `representationReasons` | `haxe_dynamic_payload` | Dynamic semantics require the runtime payload carrier |
| `representationReasons` | `haxe_string_contract` | the selected Haxe string contract determines owned or runtime storage |
| `representationReasons` | `haxe_array_contract` | Haxe Array aliases require shared runtime storage |
| `representationReasons` | `haxe_anonymous_object` | anonymous-object fields require runtime object storage |
| `representationReasons` | `haxe_function_value` | Haxe function values are reusable shared callable handles |
| `representationReasons` | `haxe_iterator_contract` | the Haxe iterator protocol uses the runtime iterator adapter |
| `representationReasons` | `admitted_portable_facade` | a per-surface contract admits the native representation |
| `representationReasons` | `haxe_core_handle` | Class and Enum values use compiler-known numeric handles |
| `representationReasons` | `haxe_bytes_identity` | haxe.io.Bytes preserves shared identity and mutation |
| `runtimeRequirements` | `object_identity` | Haxe object identity requires runtime-managed reference semantics |
| `runtimeRequirements` | `reference_mutation` | shared reference mutation requires runtime-managed storage |
| `runtimeRequirements` | `dynamic` | Dynamic-compatible values require runtime representation |
| `runtimeRequirements` | `reflection` | reflection or runtime introspection requires runtime support |
| `runtimeRequirements` | `anonymous_object` | anonymous runtime objects require runtime object storage |
| `runtimeRequirements` | `exception` | Haxe exception payload semantics require runtime support |
| `runtimeRequirements` | `nullable_compat` | nullable compatibility mode requires runtime-backed null representation |
| `runtimeRequirements` | `shared_closure_cell` | captured shared mutation requires a runtime-managed closure cell |
| `runtimeRequirements` | `platform_abstraction` | portable platform APIs require a runtime abstraction |
| `runtimeRequirements` | `haxe_array_semantics` | Haxe Array semantics require runtime array representation |
| `runtimeRequirements` | `haxe_string_semantics` | Haxe String compatibility requires runtime string representation |
| `runtimeRequirements` | `function_value` | reusable Haxe callable values need a shared runtime carrier |
| `runtimeRequirements` | `iterator_semantics` | the Haxe iterator adapter needs runtime state |
| `requiredBounds` | `clone` | the boundary needs to duplicate the payload |
| `requiredBounds` | `send` | ownership may cross a Rust thread or task |
| `requiredBounds` | `sync` | shared access may cross a Rust thread or task |
| `requiredBounds` | `static` | the payload must outlive borrowed source regions |

<!-- END GENERATED RUST REPRESENTATION VOCABULARY -->
