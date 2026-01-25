pub fn parse_float(s: &str) -> f64 {
    s.parse::<f64>().unwrap_or(f64::NAN)
}
