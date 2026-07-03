pub struct BoundTools;

impl BoundTools {
    pub fn describe<T: std::fmt::Display>(value: T) -> String {
        format!("bound:{value}")
    }
}
