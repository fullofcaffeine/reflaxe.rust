use crate::cell::{HxCell, HxRc, HxRef};
use crate::{dynamic, exception};
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
        HxRc::new(HxCell::new(Process {
            child: Some(child),
            pid,
            stdin: None,
            stdout: None,
            stderr: None,
        }))
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
        HxRc::new(HxCell::new(Process {
            child: Some(child),
            pid,
            stdin,
            stdout,
            stderr,
        }))
    }
}
