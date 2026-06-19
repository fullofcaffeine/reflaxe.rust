/// `list_native`
///
/// Typed helper module backing `haxe.ds.ListNative`.
#[derive(Debug)]
pub struct ListNative;

#[allow(non_snake_case)]
impl ListNative {
    pub fn iterator<T: Clone>(items: hxrt::array::Array<T>) -> hxrt::iter::Iter<T> {
        hxrt::iter::Iter::from_vec(items.to_vec())
    }
}
