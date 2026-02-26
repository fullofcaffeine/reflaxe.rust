/// `instant_tools`
///
/// Typed helper module backing `rust.InstantTools`.
#[derive(Debug)]
pub struct InstantTools;

#[allow(non_snake_case)]
impl InstantTools {
    pub fn now() -> std::time::Instant {
        std::time::Instant::now()
    }

    pub fn elapsed(i: &std::time::Instant) -> std::time::Duration {
        i.elapsed()
    }

    pub fn elapsedMillis(i: &std::time::Instant) -> f64 {
        i.elapsed().as_secs_f64() * 1000.0
    }
}
