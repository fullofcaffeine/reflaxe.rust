/// `mut_slice_tools`
///
/// Typed helper module backing `rust.MutSliceTools`.
#[derive(Debug)]
pub struct MutSliceTools;

#[allow(non_snake_case)]
impl MutSliceTools {
    pub fn len<T>(s: &mut [T]) -> i32 {
        s.len() as i32
    }

    pub fn get<T>(s: &mut [T], index: i32) -> Option<&T> {
        s.get(index as usize)
    }

    pub fn set<T>(s: &mut [T], index: i32, value: T) {
        s[index as usize] = value;
    }
}
