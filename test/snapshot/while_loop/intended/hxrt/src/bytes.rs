use std::fmt;

#[derive(Debug)]
pub struct Bytes {
    data: Vec<u8>,
}

impl fmt::Display for Bytes {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = String::from_utf8_lossy(&self.data);
        write!(f, "{}", s)
    }
}

impl Bytes {
    pub fn alloc(size: usize) -> Bytes {
        Bytes {
            data: vec![0u8; size],
        }
    }

    pub fn from_vec(data: Vec<u8>) -> Bytes {
        Bytes { data }
    }

    pub fn of_string(s: &str) -> Bytes {
        Bytes {
            data: s.as_bytes().to_vec(),
        }
    }

    pub fn length(&self) -> i32 {
        self.data.len() as i32
    }

    pub fn get(&self, pos: i32) -> i32 {
        self.data[pos as usize] as i32
    }

    pub fn set(&mut self, pos: i32, value: i32) {
        self.data[pos as usize] = value as u8;
    }

    pub fn as_slice(&self) -> &[u8] {
        self.data.as_slice()
    }
}
