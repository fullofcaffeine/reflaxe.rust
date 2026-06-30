use crate::array::Array;
use crate::bytes::{self, Bytes};
use crate::cell::HxRef;
use crate::{dynamic, exception, io};
use std::io::{Read, Write};
use std::process::{Child, ChildStderr, ChildStdin, ChildStdout, Command, ExitStatus, Stdio};

#[derive(Debug, Default)]
pub struct Process {
    child: Option<Child>,
    pid: i32,
    stdin: Option<ChildStdin>,
    stdout: Option<ChildStdout>,
    stderr: Option<ChildStderr>,
}

fn throw_io(err: std::io::Error) -> ! {
    exception::throw(dynamic::from(format!("{}", err)))
}

fn throw_msg(msg: &str) -> ! {
    exception::throw(dynamic::from(String::from(msg)))
}

fn throw_bounds() -> ! {
    exception::throw(dynamic::from(io::Error::OutsideBounds))
}

fn check_bytes_range(bytes_ref: &HxRef<Bytes>, pos: i32, len: i32) {
    if len < 0 {
        throw_bounds();
    }
    let bytes = bytes_ref.borrow();
    let total = bytes.length();
    if pos < 0 || pos > total || pos + len > total {
        throw_bounds();
    }
}

impl Process {
    fn child_mut(&mut self) -> &mut Child {
        match self.child.as_mut() {
            Some(c) => c,
            None => throw_msg("Process is closed"),
        }
    }

    pub fn close(&mut self) {
        self.child = None;
        self.stdin = None;
        self.stdout = None;
        self.stderr = None;
    }

    pub fn kill(&mut self) {
        let child = self.child_mut();
        if let Err(e) = child.kill() {
            throw_io(e)
        }
    }

    pub fn pid(&self) -> i32 {
        self.pid
    }

    pub fn try_wait_exit_code(&mut self) -> Option<i32> {
        let child = self.child_mut();
        match child.try_wait() {
            Ok(None) => None,
            Ok(Some(status)) => Some(exit_code(status)),
            Err(e) => throw_io(e),
        }
    }

    pub fn wait_exit_code(&mut self) -> i32 {
        let child = self.child_mut();
        match child.wait() {
            Ok(status) => exit_code(status),
            Err(e) => throw_io(e),
        }
    }

    pub fn write_stdin(&mut self, buf: &[u8]) {
        match self.stdin.as_mut() {
            Some(s) => {
                if let Err(e) = s.write_all(buf) {
                    throw_io(e)
                }
            }
            None => throw_msg("Process stdin is closed"),
        }
    }

    pub fn flush_stdin(&mut self) {
        if let Some(s) = self.stdin.as_mut() {
            let _ = s.flush();
        }
    }

    pub fn close_stdin(&mut self) {
        self.stdin = None;
    }

    /// Read up to `buf.len()` bytes from stdout/stderr into `buf`.
    /// Returns -1 on EOF, otherwise number of bytes read.
    pub fn read_stdout(&mut self, buf: &mut [u8]) -> i32 {
        match self.stdout.as_mut() {
            Some(s) => match s.read(buf) {
                Ok(0) => -1,
                Ok(n) => n as i32,
                Err(e) => throw_io(e),
            },
            None => throw_msg("Process stdout is closed"),
        }
    }

    pub fn read_stderr(&mut self, buf: &mut [u8]) -> i32 {
        match self.stderr.as_mut() {
            Some(s) => match s.read(buf) {
                Ok(0) => -1,
                Ok(n) => n as i32,
                Err(e) => throw_io(e),
            },
            None => throw_msg("Process stderr is closed"),
        }
    }
}

fn exit_code(status: ExitStatus) -> i32 {
    status.code().unwrap_or(1)
}

pub fn spawn(cmd: &str, args: Option<Vec<String>>, detached: bool) -> HxRef<Process> {
    if detached {
        // Best-effort: still allow pid + exitCode, but no stdin/out/err.
        let mut c = Command::new(cmd);
        if let Some(a) = args {
            c.args(a);
        }
        let child = match c.spawn() {
            Ok(ch) => ch,
            Err(e) => throw_io(e),
        };
        let pid = child.id() as i32;
        HxRef::new(Process {
            child: Some(child),
            pid,
            stdin: None,
            stdout: None,
            stderr: None,
        })
    } else {
        let mut c = Command::new(cmd);
        if let Some(a) = args {
            c.args(a);
        }
        c.stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = match c.spawn() {
            Ok(ch) => ch,
            Err(e) => throw_io(e),
        };
        let pid = child.id() as i32;
        let stdin = child.stdin.take();
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();
        HxRef::new(Process {
            child: Some(child),
            pid,
            stdin,
            stdout,
            stderr,
        })
    }
}

pub fn spawn_haxe<C, A>(
    cmd: C,
    args: Array<A>,
    detached: Option<bool>,
    args_provided: bool,
) -> HxRef<Process>
where
    C: AsRef<str>,
    A: AsRef<str> + Clone + Send + Sync + 'static,
{
    let cmd_text = cmd.as_ref().to_string();
    let detached_value = detached.unwrap_or(false);
    if args_provided {
        return spawn(
            cmd_text.as_str(),
            Some(
                args.iter_borrowed()
                    .map(|s| s.as_ref().to_string())
                    .collect(),
            ),
            detached_value,
        );
    }
    if cfg!(windows) {
        spawn(
            "cmd",
            Some(vec![String::from("/C"), cmd_text]),
            detached_value,
        )
    } else {
        spawn(
            "sh",
            Some(vec![String::from("-c"), cmd_text]),
            detached_value,
        )
    }
}

pub fn pid(handle: &HxRef<Process>) -> i32 {
    handle.borrow().pid()
}

pub fn wait_exit_code(handle: &HxRef<Process>) -> i32 {
    handle.borrow_mut().wait_exit_code()
}

pub fn try_wait_exit_code(handle: &HxRef<Process>) -> Option<i32> {
    handle.borrow_mut().try_wait_exit_code()
}

pub fn close(handle: &HxRef<Process>) {
    handle.borrow_mut().close();
}

pub fn kill(handle: &HxRef<Process>) {
    handle.borrow_mut().kill();
}

pub fn write_stdin(handle: &HxRef<Process>, bytes_ref: HxRef<Bytes>, pos: i32, len: i32) -> i32 {
    check_bytes_range(&bytes_ref, pos, len);
    if len == 0 {
        return 0;
    }
    let bytes_binding = bytes_ref.borrow();
    let data = bytes_binding.as_slice();
    let start = pos as usize;
    let end = (pos + len) as usize;
    handle.borrow_mut().write_stdin(&data[start..end]);
    len
}

pub fn flush_stdin(handle: &HxRef<Process>) {
    handle.borrow_mut().flush_stdin();
}

pub fn close_stdin(handle: &HxRef<Process>) {
    handle.borrow_mut().close_stdin();
}

pub fn read_stdout(handle: &HxRef<Process>, bytes_ref: HxRef<Bytes>, pos: i32, len: i32) -> i32 {
    read_pipe(handle, bytes_ref, pos, len, true)
}

pub fn read_stderr(handle: &HxRef<Process>, bytes_ref: HxRef<Bytes>, pos: i32, len: i32) -> i32 {
    read_pipe(handle, bytes_ref, pos, len, false)
}

fn read_pipe(
    handle: &HxRef<Process>,
    bytes_ref: HxRef<Bytes>,
    pos: i32,
    len: i32,
    stdout: bool,
) -> i32 {
    check_bytes_range(&bytes_ref, pos, len);
    if len == 0 {
        return 0;
    }
    let mut buf = vec![0u8; len as usize];
    let n = {
        let mut process = handle.borrow_mut();
        if stdout {
            process.read_stdout(buf.as_mut_slice())
        } else {
            process.read_stderr(buf.as_mut_slice())
        }
    };
    if n < 0 {
        return -1;
    }
    bytes::write_from_slice(&bytes_ref, pos, &buf[0..(n as usize)]);
    n
}
