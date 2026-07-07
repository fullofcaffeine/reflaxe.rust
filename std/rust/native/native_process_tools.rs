/// `native_process_tools`
///
/// Typed helper module backing `rust.process.NativeCommands`.
///
/// This module intentionally uses direct `std::process::Command` APIs and owned `Result<_, String>`
/// values so the metal no-hxrt fixture can prove Rust-native command execution without depending on
/// portable `sys.io.Process` runtime handles or Haxe stream wrappers.
#[derive(Debug)]
pub struct NativeCommands;

#[derive(Debug)]
pub struct CommandEnv {
    ops: Vec<CommandEnvOp>,
}

#[derive(Debug)]
enum CommandEnvOp {
    Set(String, String),
    Remove(String),
    Clear,
}

#[derive(Debug)]
pub struct CommandOutput {
    status_code: i32,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

fn command(program: &std::path::PathBuf, args: &Vec<String>) -> std::process::Command {
    let mut command = std::process::Command::new(program);
    for arg in args {
        command.arg(arg.as_str());
    }
    command
}

fn command_in_dir(
    program: &std::path::PathBuf,
    args: &Vec<String>,
    cwd: &std::path::PathBuf,
) -> std::process::Command {
    let mut command = command(program, args);
    command.current_dir(cwd);
    command
}

fn apply_env(command: &mut std::process::Command, env: &CommandEnv) {
    for op in &env.ops {
        match op {
            CommandEnvOp::Set(key, value) => {
                command.env(key.as_str(), value.as_str());
            }
            CommandEnvOp::Remove(key) => {
                command.env_remove(key.as_str());
            }
            CommandEnvOp::Clear => {
                command.env_clear();
            }
        }
    }
}

fn command_with_env(
    program: &std::path::PathBuf,
    args: &Vec<String>,
    env: &CommandEnv,
) -> std::process::Command {
    let mut command = command(program, args);
    apply_env(&mut command, env);
    command
}

fn command_in_dir_with_env(
    program: &std::path::PathBuf,
    args: &Vec<String>,
    cwd: &std::path::PathBuf,
    env: &CommandEnv,
) -> std::process::Command {
    let mut command = command_in_dir(program, args, cwd);
    apply_env(&mut command, env);
    command
}

fn to_command_output(output: std::process::Output) -> CommandOutput {
    CommandOutput {
        status_code: output.status.code().unwrap_or(1),
        stdout: output.stdout,
        stderr: output.stderr,
    }
}

#[allow(non_snake_case)]
impl CommandEnv {
    pub fn new() -> CommandEnv {
        CommandEnv { ops: Vec::new() }
    }

    pub fn set(&mut self, key: String, value: String) {
        self.ops.push(CommandEnvOp::Set(key, value));
    }

    pub fn remove(&mut self, key: String) {
        self.ops.push(CommandEnvOp::Remove(key));
    }

    pub fn clear(&mut self) {
        self.ops.push(CommandEnvOp::Clear);
    }
}

#[allow(non_snake_case)]
impl CommandOutput {
    pub fn statusCode(&self) -> i32 {
        self.status_code
    }

    pub fn stdoutUtf8(&self) -> Result<String, String> {
        String::from_utf8(self.stdout.clone()).map_err(|err| err.to_string())
    }

    pub fn stderrUtf8(&self) -> Result<String, String> {
        String::from_utf8(self.stderr.clone()).map_err(|err| err.to_string())
    }
}

#[allow(non_snake_case)]
impl NativeCommands {
    pub fn statusCode(program: &std::path::PathBuf, args: &Vec<String>) -> Result<i32, String> {
        let mut command = command(program, args);
        command
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|status| status.code().unwrap_or(1))
            .map_err(|err| err.to_string())
    }

    pub fn stdoutUtf8(program: &std::path::PathBuf, args: &Vec<String>) -> Result<String, String> {
        let output = command(program, args)
            .output()
            .map_err(|err| err.to_string())?;
        String::from_utf8(output.stdout).map_err(|err| err.to_string())
    }

    pub fn outputUtf8(
        program: &std::path::PathBuf,
        args: &Vec<String>,
    ) -> Result<CommandOutput, String> {
        command(program, args)
            .output()
            .map(to_command_output)
            .map_err(|err| err.to_string())
    }

    pub fn statusCodeInDir(
        program: &std::path::PathBuf,
        args: &Vec<String>,
        cwd: &std::path::PathBuf,
    ) -> Result<i32, String> {
        let mut command = command_in_dir(program, args, cwd);
        command
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|status| status.code().unwrap_or(1))
            .map_err(|err| err.to_string())
    }

    pub fn outputUtf8InDir(
        program: &std::path::PathBuf,
        args: &Vec<String>,
        cwd: &std::path::PathBuf,
    ) -> Result<CommandOutput, String> {
        command_in_dir(program, args, cwd)
            .output()
            .map(to_command_output)
            .map_err(|err| err.to_string())
    }

    pub fn statusCodeWithEnv(
        program: &std::path::PathBuf,
        args: &Vec<String>,
        env: &CommandEnv,
    ) -> Result<i32, String> {
        let mut command = command_with_env(program, args, env);
        command
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|status| status.code().unwrap_or(1))
            .map_err(|err| err.to_string())
    }

    pub fn outputUtf8WithEnv(
        program: &std::path::PathBuf,
        args: &Vec<String>,
        env: &CommandEnv,
    ) -> Result<CommandOutput, String> {
        command_with_env(program, args, env)
            .output()
            .map(to_command_output)
            .map_err(|err| err.to_string())
    }

    pub fn statusCodeInDirWithEnv(
        program: &std::path::PathBuf,
        args: &Vec<String>,
        cwd: &std::path::PathBuf,
        env: &CommandEnv,
    ) -> Result<i32, String> {
        let mut command = command_in_dir_with_env(program, args, cwd, env);
        command
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|status| status.code().unwrap_or(1))
            .map_err(|err| err.to_string())
    }

    pub fn outputUtf8InDirWithEnv(
        program: &std::path::PathBuf,
        args: &Vec<String>,
        cwd: &std::path::PathBuf,
        env: &CommandEnv,
    ) -> Result<CommandOutput, String> {
        command_in_dir_with_env(program, args, cwd, env)
            .output()
            .map(to_command_output)
            .map_err(|err| err.to_string())
    }
}
