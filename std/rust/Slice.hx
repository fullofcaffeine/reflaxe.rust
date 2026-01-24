package rust;

/**
 * rust.Slice<T>
 *
 * Represents a borrowed slice (`&[T]`) in Rust output.
 *
 * IMPORTANT:
 * - Like `Ref<T>`, this is a borrowed view; avoid storing long-lived slices.
 * - Prefer constructing via `SliceTools.fromVec` or borrow-scoped helpers.
 */
@:coreType
extern abstract Slice<T> {
}
