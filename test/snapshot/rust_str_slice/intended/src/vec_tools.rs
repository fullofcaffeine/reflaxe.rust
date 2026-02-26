/// `vec_tools`
///
/// Typed helper module backing `rust.VecTools`.
#[derive(Debug)]
pub struct VecTools;

#[allow(non_snake_case)]
impl VecTools {
    pub fn fromArray<T: Clone>(a: hxrt::array::Array<T>) -> Vec<T> {
        a.to_vec()
    }

    pub fn toArray<T: Clone>(v: Vec<T>) -> hxrt::array::Array<T> {
        hxrt::array::Array::<T>::from_vec(v)
    }

    pub fn len<T>(v: &Vec<T>) -> i32 {
        v.len() as i32
    }

    pub fn get<T: Clone>(v: &Vec<T>, index: i32) -> Option<T> {
        v.get(index as usize).cloned()
    }

    pub fn getRef<T>(v: &Vec<T>, index: i32) -> Option<&T> {
        v.get(index as usize)
    }

    pub fn getMut<T>(v: &mut Vec<T>, index: i32) -> Option<&mut T> {
        v.get_mut(index as usize)
    }

    pub fn set<T>(v: Vec<T>, index: i32, value: T) -> Vec<T> {
        let mut out = v;
        out[index as usize] = value;
        out
    }
}
