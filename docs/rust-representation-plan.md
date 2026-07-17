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

This first modeling slice does not change generated Rust. Later slices route existing lowering and
boundary behavior through these decisions and embed the canonical decision component in the runtime
plan report.

## How

Run `node scripts/ci/rust-representation-policy.js --write` after an intentional vocabulary change.
The generator updates the Haxe enum blocks, the component JSON Schema, and the reference table below.
CI and pre-commit use `--check` and compare every generated consumer byte-for-byte.

Runtime-reason entries also declare their versioned consumers. The published `runtime_plan.json`
v4 vocabulary remains immutable, while the new representation-decision v1 component may model
additional reasons before a future runtime-report version deliberately admits them.

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
| `sourceValueKinds` | `string` | a Haxe String under the selected nullable or owned contract |
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
