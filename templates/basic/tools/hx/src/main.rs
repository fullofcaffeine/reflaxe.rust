use std::env;
use std::path::PathBuf;
use std::process::{exit, Command};

fn script_path() -> PathBuf {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest_dir.join("../../scripts/dev/cargo-hx.sh")
}

fn main() {
    let script = script_path();
    if !script.exists() {
        eprintln!("error: missing script {}", script.display());
        exit(2);
    }

    let mut cmd = Command::new("bash");
    cmd.arg(script);
    for arg in env::args().skip(1) {
        cmd.arg(arg);
    }

    match cmd.status() {
        Ok(status) => {
            if let Some(code) = status.code() {
                exit(code);
            }
            exit(1);
        }
        Err(err) => {
            eprintln!("error: failed to run cargo-hx driver: {err}");
            exit(2);
        }
    }
}

