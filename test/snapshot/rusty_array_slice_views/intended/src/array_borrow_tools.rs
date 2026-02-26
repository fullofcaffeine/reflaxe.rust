/// `array_borrow_tools`
///
/// Typed helper module backing `rust.ArrayBorrow`.
///
/// Why
/// - `rust.ArrayBorrow` needs Rust callback aliases (`Fn(&[T])` / `Fn(&mut [T])`) that are
///   awkward to express purely in Haxe extern signatures while keeping generated output clear.
/// - Centralizing this bridge keeps first-party Haxe code typed and removes inline raw fallback.
///
/// How
/// - Delegates directly to `hxrt::array::with_slice` / `with_mut_slice`.
/// - Callback types use the same `crate::HxDynRef` alias the generated crate uses for Haxe
///   function values.
#[derive(Debug)]
pub struct ArrayBorrowTools;

#[allow(non_snake_case)]
impl ArrayBorrowTools {
    pub fn withSlice<T, R>(
        array: &hxrt::array::Array<T>,
        f: crate::HxDynRef<dyn Fn(&[T]) -> R + Send + Sync>,
    ) -> R {
        hxrt::array::with_slice(array, f)
    }

    pub fn withMutSlice<T, R>(
        array: &hxrt::array::Array<T>,
        f: crate::HxDynRef<dyn Fn(&mut [T]) -> R + Send + Sync>,
    ) -> R {
        hxrt::array::with_mut_slice(array, f)
    }
}
