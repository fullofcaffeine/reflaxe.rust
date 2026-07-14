#!/usr/bin/env python3

"""Prove native lock callbacks reject same-handle reentry without weakening atomicity.

Why
---
`rust.concurrent` callback helpers intentionally hold a real Rust lock guard while user code runs.
Without runtime handle-identity detection, touching that same handle from the callback blocks forever.
The compiler cannot prove the callback's dynamic call graph or which shared handle it will receive.

What
----
The contract compiles one Haxe program and executes every mutex/RwLock callback shape in a separate
process with a hard timeout. Same-handle access must throw the stable Haxe-visible identifier
`HXRT-LOCK-REENTRANCY`; callback throws must release guard state; consistently ordered access to a
different handle remains valid.

How
---
Each mode is a real generated Rust executable invocation. A timeout is treated as the original
deadlock defect, while a nonzero exit proves the runtime did not return through Haxe `catch`.
"""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile

from python_tool_commands import project_haxe_command


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "test" / "runtime_e2e" / "native_lock_reentrancy"
TIMEOUT_SECONDS = 5


def run_checked(command: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> None:
    completed = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True)
    if completed.returncode != 0:
        output = "\n".join(part for part in (completed.stdout, completed.stderr) if part)
        raise AssertionError(f"command failed ({completed.returncode}): {' '.join(command)}\n{output}")


def assert_mode(executable: Path, mode: str, expected: str) -> None:
    try:
        completed = subprocess.run(
            [str(executable), mode],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=TIMEOUT_SECONDS,
            text=True,
        )
    except subprocess.TimeoutExpired as error:
        raise AssertionError(f"{mode} deadlocked beyond {TIMEOUT_SECONDS}s") from error

    if completed.returncode != 0:
        raise AssertionError(
            f"{mode} terminated instead of returning through Haxe catch (exit {completed.returncode})\n"
            f"stdout={completed.stdout!r}\nstderr={completed.stderr!r}"
        )

    actual = completed.stdout.replace("\r\n", "\n")
    if actual != expected:
        raise AssertionError(f"{mode} stdout mismatch\nexpected={expected!r}\nactual={actual!r}")
    if completed.stderr:
        raise AssertionError(f"{mode} wrote unexpected stderr: {completed.stderr!r}")


def main() -> int:
    reentry_modes = {
        "mutex-update": "mutex_update",
        "mutex-with-ref": "mutex_with_ref",
        "mutex-with-mut": "mutex_with_mut",
        "rw-lock-update": "rw_lock_update",
        "rw-lock-read-to-write": "rw_lock_read_to_write",
        "rw-lock-write-to-read": "rw_lock_write_to_read",
    }
    for operation in ("get", "set", "replace", "update", "with-ref", "with-mut"):
        reentry_modes[f"mutex-inner-{operation}"] = f"mutex_inner_{operation.replace('-', '_')}"
    for operation in ("read", "write", "replace", "update", "with-read", "with-write"):
        reentry_modes[f"rw-lock-inner-{operation}"] = f"rw_lock_inner_{operation.replace('-', '_')}"

    with tempfile.TemporaryDirectory(prefix="reflaxe-rust-lock-reentry-") as temporary:
        temp_root = Path(temporary)
        generated = temp_root / "generated"
        target = temp_root / "target"
        haxe_command = project_haxe_command(ROOT, [
            "-cp",
            str(FIXTURE),
            "-lib",
            "reflaxe.rust",
            "-D",
            "reflaxe_rust_profile=metal",
            "-D",
            "reflaxe_rust_strict_examples",
            "-D",
            "rust_no_build",
            "-D",
            "rust_crate=native_lock_reentrancy_contract",
            "-D",
            f"rust_output={generated}",
            "-main",
            "Main",
        ])
        run_checked(haxe_command, cwd=ROOT)

        cargo_env = os.environ.copy()
        cargo_env["CARGO_TARGET_DIR"] = str(target)
        run_checked(
            ["cargo", "build", "-q", "--manifest-path", str(generated / "Cargo.toml")],
            cwd=ROOT,
            env=cargo_env,
        )

        executable = target / "debug" / (
            "native_lock_reentrancy_contract.exe" if os.name == "nt" else "native_lock_reentrancy_contract"
        )
        if not executable.is_file():
            raise AssertionError(f"generated lock-contract executable is missing: {executable}")

        for mode, label in reentry_modes.items():
            assert_mode(
                executable,
                mode,
                f"{label}=HXRT-LOCK-REENTRANCY\n{label}_continued=true\n",
            )

        assert_mode(executable, "callback-throw-cleanup", "callback_throw_cleanup=true\n")
        assert_mode(executable, "caught-reentry-keeps-scope", "caught_reentry_scope=true\n")
        assert_mode(
            executable,
            "cross-handle-order",
            "cross_handle_mutex=3\ncross_handle_rw_lock=7\n",
        )

    print("[native-lock-reentrancy] OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"[native-lock-reentrancy] ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
