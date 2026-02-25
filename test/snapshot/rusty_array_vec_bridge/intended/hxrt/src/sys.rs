//! `hxrt::sys`
//!
//! Runtime-backed helpers for `std/Sys.cross.hx` and `sys.io.Stdin`.
//!
//! Why
//! - `Sys` and `Stdin` previously used many inline `untyped __rust__` expressions.
//! - Those expressions become `ERaw` fallback nodes in metal diagnostics and hide boundaries
//!   across many call sites.
//!
//! What
//! - A typed runtime API for common process/environment/time/stdin operations.
//!
//! How
//! - Input parameters use trait-based typing where portable (`HxString`) and metal (`String`)
//!   call sites differ.
//! - Return values use concrete, non-ambiguous forms (for example `String`) where generated
//!   wrappers already perform profile-specific conversion.
//! - `stdin_read_bytes` writes directly into `hxrt::bytes::Bytes` via `write_from_slice`.

use crate::array::Array;
use crate::bytes::{self, Bytes};
use crate::cell::HxRef;
use crate::string::HxString;
use std::io::Read;
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub fn print<T>(value: T)
where
    T: std::fmt::Display,
{
    print!("{value}");
}

pub fn println<T>(value: T)
where
    T: std::fmt::Display,
{
    println!("{value}");
}

pub fn args<S>() -> Array<S>
where
    S: From<String>,
{
    Array::from_vec(std::env::args().skip(1).map(S::from).collect())
}

pub fn get_env<N>(name: N) -> String
where
    N: AsRef<str>,
{
    std::env::var(name.as_ref())
        .ok()
        .unwrap_or_else(String::new)
}

pub trait IntoEnvValue {
    fn into_env_value(self) -> Option<String>;
}

impl IntoEnvValue for HxString {
    fn into_env_value(self) -> Option<String> {
        self.as_deref().map(String::from)
    }
}

impl IntoEnvValue for String {
    fn into_env_value(self) -> Option<String> {
        Some(self)
    }
}

impl IntoEnvValue for Option<String> {
    fn into_env_value(self) -> Option<String> {
        self
    }
}

impl IntoEnvValue for Option<HxString> {
    fn into_env_value(self) -> Option<String> {
        self.and_then(|value| value.as_deref().map(String::from))
    }
}

pub fn put_env<N, V>(name: N, value: V)
where
    N: AsRef<str>,
    V: IntoEnvValue,
{
    if let Some(value) = value.into_env_value() {
        std::env::set_var(name.as_ref(), value.as_str());
    } else {
        std::env::remove_var(name.as_ref());
    }
}

pub fn sleep(seconds: f64) {
    let millis = (seconds.max(0.0) * 1000.0) as u64;
    std::thread::sleep(Duration::from_millis(millis));
}

pub fn get_cwd() -> String {
    std::env::current_dir()
        .unwrap()
        .to_string_lossy()
        .to_string()
}

pub fn set_cwd<P>(path: P)
where
    P: AsRef<str>,
{
    std::env::set_current_dir(path.as_ref()).unwrap();
}

fn normalize_system_name(os: &str) -> String {
    match os {
        "windows" => String::from("Windows"),
        "linux" => String::from("Linux"),
        "macos" => String::from("Mac"),
        "freebsd" | "netbsd" | "openbsd" => String::from("BSD"),
        _ => String::from(os),
    }
}

pub fn system_name() -> String {
    normalize_system_name(std::env::consts::OS)
}

pub fn command<C, A>(cmd: C, args: Array<A>) -> i32
where
    C: AsRef<str>,
    A: AsRef<str> + Clone,
{
    if !args.is_null() {
        let mut c = Command::new(cmd.as_ref());
        let mut i: i32 = 0;
        while i < args.len() as i32 {
            let arg = args.get_unchecked(i as usize);
            c.arg(arg.as_ref());
            i += 1;
        }
        return c.status().unwrap().code().unwrap_or(1) as i32;
    }

    if cfg!(windows) {
        Command::new("cmd")
            .arg("/C")
            .arg(cmd.as_ref())
            .status()
            .unwrap()
            .code()
            .unwrap_or(1) as i32
    } else {
        Command::new("sh")
            .arg("-c")
            .arg(cmd.as_ref())
            .status()
            .unwrap()
            .code()
            .unwrap_or(1) as i32
    }
}

pub fn exit(code: i32) -> ! {
    std::process::exit(code);
}

pub fn time() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs_f64()
}

pub fn program_path() -> String {
    std::env::current_exe()
        .unwrap()
        .to_string_lossy()
        .to_string()
}

pub fn stdin_read_byte() -> i32 {
    let mut buf = [0u8; 1];
    match std::io::stdin().read(&mut buf) {
        Ok(0) => -1,
        Ok(_) => buf[0] as i32,
        Err(_) => -1,
    }
}

pub fn stdin_read_bytes(dst: HxRef<Bytes>, pos: i32, len: i32) -> i32 {
    if len <= 0 {
        return 0;
    }

    let mut buf = vec![0u8; len as usize];
    match std::io::stdin().read(&mut buf) {
        Ok(0) => 0,
        Ok(n) => {
            bytes::write_from_slice(&dst, pos, &buf[..n]);
            n as i32
        }
        Err(_) => 0,
    }
}
