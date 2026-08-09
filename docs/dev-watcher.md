# Dev Watcher (Fast Edit-Compile-Run Loop)

This watcher gives you a fast local loop while building Haxe -> Rust apps:

1. You edit `.hx` files.
2. The watcher recompiles your `.hxml` target.
3. It runs Cargo automatically (`run` or `test`) so you get immediate feedback.

You do not need to know compiler internals to use it.

## Incremental compile cache (default)

In watch mode, the script starts its own Haxe compile server (`haxe --wait`) and compiles with `--connect`.

- First compile: warms up the compile server cache.
- Next compiles: usually faster because Haxe can reuse typed/incremental state.
- When you stop the watcher: it stops the owned compile server automatically.

`--once` does a direct compile by default (no server), which is useful for one-off checks.

## Install `watchexec` once

The watcher script uses [`watchexec`](https://github.com/watchexec/watchexec).

Install with either:

- Homebrew: [`brew install watchexec`](https://formulae.brew.sh/formula/watchexec)
- Cargo: [`cargo install watchexec-cli`](https://crates.io/crates/watchexec-cli)

## Quick start

From an application or example directory:

```bash
cargo hx dev
```

That runs in `run` mode by default:

- choose the same `compile*.hxml` file as the one-shot `cargo hx` commands
- compile Haxe with the selected `.hxml`
- run generated Rust with `cargo run -q`
- repeat on file changes

For example, from the compiler checkout:

```bash
cd examples/hello
cargo hx dev
```

Mode guardrail:

- `run`/`test` modes force compile to codegen-only (`-D rust_no_build`) to avoid double cargo invocations when an `.hxml` default already sets `rust_cargo_subcommand=run`.
- `build` mode forces `rust_cargo_subcommand=build` so it never accidentally runs/tests during compile.

## Common commands

Run tests on every change:

```bash
cargo hx dev --mode test
```

Compile only (no `cargo run` / `cargo test`):

```bash
cargo hx dev --mode build
```

Run one cycle and exit (no watcher required):

```bash
cargo hx dev --once
```

Disable the compile server (force direct Haxe compile each cycle):

```bash
cargo hx dev --no-haxe-server
```

Equivalent environment override:

```bash
HAXE_RUST_WATCH_NO_SERVER=1 cargo hx dev
```

## Arguments

- `--profile <name>`: select `compile.<profile>.hxml` when present.
- `--hxml <path>`: explicitly select a build target instead of automatic selection.
- `--mode <run|build|test>`: per-change action. Default `run`.
- `--watch <path>`: add extra paths to watch (repeatable).
- `--debounce-ms <n>`: delay before rebuild. Default `250`.
- `--once`: run one cycle without starting file watch.
- `--no-haxe-server`: skip the incremental Haxe compile server and compile directly.
- `--haxe-bin <path>`: override Haxe binary.
- `--cargo-bin <path>`: override Cargo binary.

The lower-level `bash scripts/dev/watch-haxe-rust.sh --hxml ...` command remains available for
custom tooling. Application developers normally should not need it.

## Practical tips

- Start with one example or app `.hxml`, then switch to your project target.
- Use `--mode test` in active development for faster feedback on regressions.
- Keep generated output out of your watch roots to avoid loops (the script already ignores common generated folders).
- If your compile behavior ever looks stale, restart watch mode once to reset the compile server cache.

## Related docs

- [Start Here](start-here.md)
- [Workflow (Haxe -> Rust -> native)](workflow.md)
- [Defines reference](defines-reference.md)
