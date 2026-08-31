//! `hxrt::sys`
//!
//! Runtime-backed helpers for the Rust-target `Sys` override and `sys.io.Std*`.
//!
//! Why
//! - `Sys` and `sys.io.Std*` previously used many inline `untyped __rust__` expressions.
//! - Those expressions become `ERaw` fallback nodes in metal diagnostics and hide boundaries
//!   across many call sites.
//!
//! What
//! - A typed runtime API for common process/environment/time/std stream operations.
//!
//! How
//! - Input parameters use trait-based typing where portable (`HxString`) and metal (`String`)
//!   call sites differ.
//! - Return values keep nullable boundaries explicit where required by Haxe contracts
//!   (for example `get_env -> Option<String>` for `Sys.getEnv : Null<String>`).
//! - Normal `Sys` failures throw portable `HxString` values; standard-stream failures throw typed
//!   `haxe.io.Error.Custom` values. Neither route uses a Rust panic as an application error.
//! - `stdin_read_bytes` and std-stream byte writes operate directly on `hxrt::bytes::Bytes`
//!   via typed runtime buffers.

use crate::array::Array;
use crate::bytes::{self, Bytes};
use crate::cell::HxRef;
use crate::string::HxString;
use crate::{dynamic, exception, io as hx_io};
use std::io::{Read, Write};
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// Converts a normal Rust failure into the Haxe-visible error family owned by the calling API.
///
/// Why
/// - A Rust `unwrap()` panic is not a Haxe throw and therefore bypasses generated `try/catch`.
/// - Standard streams additionally promise typed `haxe.io.Error` failures, while core `Sys`
///   operations historically expose a general catchable error value.
///
/// What
/// - `System` throws a descriptive Haxe string for `Sys` environment/process/path failures.
/// - `Stream` throws `haxe.io.Error.Custom(...)` for `haxe.io.Input`/`Output` operations.
///
/// How
/// - Every fallible operation passes its `Result` through `resolve`; EOF and absent environment
///   variables remain explicit non-error branches before this boundary is invoked.
#[derive(Clone, Copy)]
enum PortableFailure {
    System(&'static str),
    Stream(&'static str),
}

impl PortableFailure {
    fn resolve<T, E>(self, result: Result<T, E>) -> T
    where
        E: std::fmt::Display,
    {
        match result {
            Ok(value) => value,
            Err(error) => self.raise(error),
        }
    }

    fn raise<E>(self, error: E) -> !
    where
        E: std::fmt::Display,
    {
        let operation = match self {
            PortableFailure::System(operation) | PortableFailure::Stream(operation) => operation,
        };
        let message = format!("{operation}: {error}");
        match self {
            PortableFailure::System(_) => exception::throw(dynamic::from(HxString::from(message))),
            PortableFailure::Stream(_) => exception::throw(dynamic::from(hx_io::Error::Custom(
                dynamic::from(HxString::from(message)),
            ))),
        }
    }
}

#[derive(Clone, Copy)]
enum EnvNameUse {
    Lookup,
    Mutation,
}

/// Rejects environment names that cannot cross the selected Rust environment boundary safely.
///
/// Why: `std::env::{var,set_var,remove_var}` do not consistently return `Result` for malformed
/// names, so validation must happen before crossing that native boundary.
/// What: NUL is invalid for both paths. Empty names and `=` are additionally rejected for mutation,
/// while lookup preserves host behavior for special/absent keys such as Windows `=C:` entries.
/// How: The same `PortableFailure::System` path used by ordinary Rust `Result` errors owns them.
fn validate_env_name(operation: &'static str, name: &str, use_kind: EnvNameUse) {
    let invalid_mutation =
        matches!(use_kind, EnvNameUse::Mutation) && (name.is_empty() || name.contains('='));
    if invalid_mutation || name.as_bytes().contains(&0) {
        PortableFailure::System(operation)
            .raise("environment variable name is empty or contains '=' or NUL");
    }
}

/// Rejects NUL-containing environment values before `std::env::set_var` can panic.
///
/// Why: A malformed Haxe string is application input, not a Rust invariant failure.
/// What: The invalid value becomes a catchable Haxe system error.
/// How: Validation reuses the single portable system-failure boundary.
fn validate_env_value(operation: &'static str, value: &str) {
    if value.as_bytes().contains(&0) {
        PortableFailure::System(operation).raise("environment variable value contains NUL");
    }
}

pub fn print<T>(value: T)
where
    T: std::fmt::Display,
{
    let mut stdout = std::io::stdout().lock();
    PortableFailure::Stream("Sys.print").resolve(write!(stdout, "{value}"));
}

pub fn println<T>(value: T)
where
    T: std::fmt::Display,
{
    let mut stdout = std::io::stdout().lock();
    PortableFailure::Stream("Sys.println").resolve(writeln!(stdout, "{value}"));
}

pub fn args<S>() -> Array<S>
where
    S: From<String>,
{
    let mut values = Vec::new();
    for value in std::env::args_os().skip(1) {
        let value = match value.into_string() {
            Ok(value) => value,
            Err(_) => PortableFailure::System("Sys.args")
                .raise("command-line argument is not valid Unicode"),
        };
        values.push(S::from(value));
    }
    Array::from_vec(values)
}

pub fn get_env<N>(name: N) -> Option<String>
where
    N: AsRef<str>,
{
    let name = name.as_ref();
    validate_env_name("Sys.getEnv", name, EnvNameUse::Lookup);
    match std::env::var(name) {
        Ok(value) => Some(value),
        Err(std::env::VarError::NotPresent) => None,
        Err(error) => PortableFailure::System("Sys.getEnv").raise(error),
    }
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
    let name = name.as_ref();
    validate_env_name("Sys.putEnv", name, EnvNameUse::Mutation);
    if let Some(value) = value.into_env_value() {
        validate_env_value("Sys.putEnv", value.as_str());
        std::env::set_var(name, value.as_str());
    } else {
        std::env::remove_var(name);
    }
}

pub fn environment_pairs<S>() -> Array<Array<S>>
where
    S: From<String>,
{
    let mut pairs: Vec<Array<S>> = Vec::new();
    for (key, value) in std::env::vars_os() {
        let key = match key.into_string() {
            Ok(key) => key,
            Err(_) => PortableFailure::System("Sys.environment")
                .raise("environment variable name is not valid Unicode"),
        };
        let value = match value.into_string() {
            Ok(value) => value,
            Err(_) => PortableFailure::System("Sys.environment")
                .raise("environment variable value is not valid Unicode"),
        };
        pairs.push(Array::from_vec(vec![S::from(key), S::from(value)]));
    }
    Array::from_vec(pairs)
}

pub fn sleep(seconds: f64) {
    let millis = (seconds.max(0.0) * 1000.0) as u64;
    std::thread::sleep(Duration::from_millis(millis));
}

pub fn get_cwd() -> String {
    PortableFailure::System("Sys.getCwd")
        .resolve(std::env::current_dir())
        .to_string_lossy()
        .to_string()
}

pub fn set_cwd<P>(path: P)
where
    P: AsRef<str>,
{
    PortableFailure::System("Sys.setCwd").resolve(std::env::set_current_dir(path.as_ref()));
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
        let status = PortableFailure::System("Sys.command").resolve(c.status());
        return status.code().unwrap_or(1);
    }

    let status = if cfg!(windows) {
        Command::new("cmd").arg("/C").arg(cmd.as_ref()).status()
    } else {
        Command::new("sh").arg("-c").arg(cmd.as_ref()).status()
    };
    let status = PortableFailure::System("Sys.command").resolve(status);
    status.code().unwrap_or(1)
}

pub fn exit(code: i32) -> ! {
    std::process::exit(code);
}

pub fn time() -> f64 {
    PortableFailure::System("Sys.time")
        .resolve(SystemTime::now().duration_since(UNIX_EPOCH))
        .as_secs_f64()
}

pub fn program_path() -> String {
    PortableFailure::System("Sys.programPath")
        .resolve(std::env::current_exe())
        .to_string_lossy()
        .to_string()
}

fn read_byte_from<R>(reader: &mut R) -> i32
where
    R: Read,
{
    let mut buf = [0u8; 1];
    match reader.read(&mut buf) {
        Ok(0) => -1,
        Ok(_) => buf[0] as i32,
        Err(error) => PortableFailure::Stream("Sys.stdin.readByte").raise(error),
    }
}

pub fn stdin_read_byte() -> i32 {
    read_byte_from(&mut std::io::stdin().lock())
}

fn read_bytes_from<R>(reader: &mut R, dst: &HxRef<Bytes>, pos: i32, len: i32) -> i32
where
    R: Read,
{
    if len <= 0 {
        return 0;
    }

    let mut buf = vec![0u8; len as usize];
    match reader.read(&mut buf) {
        Ok(0) => 0,
        Ok(n) => {
            bytes::write_from_slice(dst, pos, &buf[..n]);
            n as i32
        }
        Err(error) => PortableFailure::Stream("Sys.stdin.readBytes").raise(error),
    }
}

pub fn stdin_read_bytes(dst: HxRef<Bytes>, pos: i32, len: i32) -> i32 {
    read_bytes_from(&mut std::io::stdin().lock(), &dst, pos, len)
}

fn write_byte_to<W>(writer: &mut W, value: i32, failure: PortableFailure)
where
    W: Write,
{
    failure.resolve(writer.write_all(&[((value & 0xFF) as u8)]));
}

fn write_bytes_to<W>(
    writer: &mut W,
    src: &HxRef<Bytes>,
    pos: i32,
    len: i32,
    failure: PortableFailure,
) -> i32
where
    W: Write,
{
    if len <= 0 {
        return 0;
    }
    let b = src.borrow();
    let data = b.as_slice();
    let start = pos as usize;
    let end = (pos + len) as usize;
    failure.resolve(writer.write_all(&data[start..end]));
    len
}

fn flush_to<W>(writer: &mut W, failure: PortableFailure)
where
    W: Write,
{
    failure.resolve(writer.flush());
}

pub fn stdout_write_byte(value: i32) {
    write_byte_to(
        &mut std::io::stdout().lock(),
        value,
        PortableFailure::Stream("Sys.stdout.writeByte"),
    );
}

pub fn stdout_write_bytes(src: HxRef<Bytes>, pos: i32, len: i32) -> i32 {
    write_bytes_to(
        &mut std::io::stdout().lock(),
        &src,
        pos,
        len,
        PortableFailure::Stream("Sys.stdout.writeBytes"),
    )
}

pub fn stdout_flush() {
    flush_to(
        &mut std::io::stdout().lock(),
        PortableFailure::Stream("Sys.stdout.flush"),
    );
}

pub fn stderr_write_byte(value: i32) {
    write_byte_to(
        &mut std::io::stderr().lock(),
        value,
        PortableFailure::Stream("Sys.stderr.writeByte"),
    );
}

pub fn stderr_write_bytes(src: HxRef<Bytes>, pos: i32, len: i32) -> i32 {
    write_bytes_to(
        &mut std::io::stderr().lock(),
        &src,
        pos,
        len,
        PortableFailure::Stream("Sys.stderr.writeBytes"),
    )
}

pub fn stderr_flush() {
    flush_to(
        &mut std::io::stderr().lock(),
        PortableFailure::Stream("Sys.stderr.flush"),
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io;

    struct FailingIo;

    impl Read for FailingIo {
        fn read(&mut self, _buffer: &mut [u8]) -> io::Result<usize> {
            Err(io::Error::other("injected read failure"))
        }
    }

    impl Write for FailingIo {
        fn write(&mut self, _buffer: &[u8]) -> io::Result<usize> {
            Err(io::Error::new(
                io::ErrorKind::BrokenPipe,
                "injected write failure",
            ))
        }

        fn flush(&mut self) -> io::Result<()> {
            Err(io::Error::new(
                io::ErrorKind::BrokenPipe,
                "injected flush failure",
            ))
        }
    }

    fn expect_stream_failure(operation: impl FnOnce()) {
        let caught = exception::catch_unwind(operation);
        let payload = match caught {
            Ok(()) => panic!("expected Haxe stream failure"),
            Err(payload) => payload,
        };
        match payload.downcast_ref::<hx_io::Error>() {
            Some(hx_io::Error::Custom(_)) => {}
            _ => panic!("expected haxe.io.Error.Custom payload"),
        }
    }

    #[test]
    fn stdin_error_is_not_eof() {
        expect_stream_failure(|| {
            let _ = read_byte_from(&mut FailingIo);
        });
        assert_eq!(read_byte_from(&mut io::empty()), -1);

        let destination = HxRef::new(Bytes::alloc(4));
        expect_stream_failure(|| {
            let _ = read_bytes_from(&mut FailingIo, &destination, 0, 4);
        });
        assert_eq!(read_bytes_from(&mut io::empty(), &destination, 0, 4), 0);
    }

    #[test]
    fn standard_stream_write_and_flush_errors_are_haxe_io_errors() {
        expect_stream_failure(|| {
            write_byte_to(&mut FailingIo, 65, PortableFailure::Stream("test.write"))
        });
        expect_stream_failure(|| flush_to(&mut FailingIo, PortableFailure::Stream("test.flush")));
    }

    #[test]
    fn system_failures_are_catchable_haxe_values() {
        let caught = exception::catch_unwind(|| {
            PortableFailure::System("test.system")
                .resolve::<(), _>(Err(io::Error::new(io::ErrorKind::NotFound, "injected")));
        });
        let payload = match caught {
            Ok(()) => panic!("expected Haxe system failure"),
            Err(payload) => payload,
        };
        assert!(payload.downcast_ref::<HxString>().is_some());
    }
}
