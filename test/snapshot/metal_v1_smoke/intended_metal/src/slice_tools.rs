/// `slice_tools`
///
/// Typed helper module backing `rust.SliceTools`.
#[derive(Debug)]
pub struct SliceTools;

#[allow(non_snake_case)]
impl SliceTools {
    pub fn len<T>(s: &[T]) -> i32 {
        s.len() as i32
    }

    pub fn get<T>(s: &[T], index: i32) -> Option<&T> {
        s.get(index as usize)
    }

    pub fn toArray<T: Clone>(s: &[T]) -> hxrt::array::Array<T> {
        hxrt::array::Array::<T>::from_vec(s.to_vec())
    }
}
