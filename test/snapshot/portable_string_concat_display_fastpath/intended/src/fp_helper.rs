/// `fp_helper`
///
/// Typed helper module backing `haxe.io.FPHelper` IEEE-754 bit reinterpretation.
#[derive(Debug)]
pub struct FPHelper;

#[allow(non_snake_case)]
impl FPHelper {
    pub fn floatToI32(v: f64) -> i32 {
        (v as f32).to_bits() as i32
    }

    pub fn i32ToFloat(v: i32) -> f64 {
        f32::from_bits(v as u32) as f64
    }

    pub fn doubleToI64High(v: f64) -> i32 {
        (v.to_bits() >> 32) as i32
    }

    pub fn doubleToI64Low(v: f64) -> i32 {
        ((v.to_bits() & 0xFFFF_FFFFu64) as u32) as i32
    }

    pub fn i64ToDouble(low: i32, high: i32) -> f64 {
        f64::from_bits(((high as u64) << 32) | ((low as u32) as u64))
    }
}
