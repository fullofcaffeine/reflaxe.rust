/// `clone_tools`
///
/// Tiny typed helper backing `rust.CloneTools`.
#[derive(Debug)]
pub struct CloneTools;

#[allow(non_snake_case)]
impl CloneTools {
    pub fn cloneValue<T: Clone>(value: &T) -> T {
        value.clone()
    }
}
