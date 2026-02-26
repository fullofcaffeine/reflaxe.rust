/// `iter_tools`
///
/// Typed helper module backing `rust.IterTools`.
#[derive(Debug)]
pub struct IterTools;

#[allow(non_snake_case)]
impl IterTools {
    pub fn fromVec<T>(v: Vec<T>) -> std::vec::IntoIter<T> {
        v.into_iter()
    }
}
