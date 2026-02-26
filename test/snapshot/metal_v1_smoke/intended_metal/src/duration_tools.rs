/// `duration_tools`
///
/// Typed helper module backing `rust.DurationTools`.
#[derive(Debug)]
pub struct DurationTools;

#[allow(non_snake_case)]
impl DurationTools {
    pub fn fromMillis(ms: i32) -> std::time::Duration {
        std::time::Duration::from_millis(ms.max(0) as u64)
    }

    pub fn fromSecs(secs: i32) -> std::time::Duration {
        std::time::Duration::from_secs(secs.max(0) as u64)
    }

    pub fn asMillis(d: std::time::Duration) -> f64 {
        d.as_secs_f64() * 1000.0
    }

    pub fn sleep(d: std::time::Duration) {
        std::thread::sleep(d);
    }
}
