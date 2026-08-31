pub struct Int32Tools;

impl Int32Tools {
    pub fn wrapping_add(a: i32, b: i32) -> i32 {
        a.wrapping_add(b)
    }

    pub fn wrapping_sub(a: i32, b: i32) -> i32 {
        a.wrapping_sub(b)
    }

    pub fn wrapping_mul(a: i32, b: i32) -> i32 {
        a.wrapping_mul(b)
    }

    pub fn wrapping_neg(a: i32) -> i32 {
        a.wrapping_neg()
    }

    pub fn ucompare(a: i32, b: i32) -> i32 {
        let ua = a as u32;
        let ub = b as u32;
        if ua < ub {
            -1
        } else if ua > ub {
            1
        } else {
            0
        }
    }
}
