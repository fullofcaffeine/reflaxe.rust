# Dev Watcher (Fast Edit-Compile-Run Loop)

This watcher gives you a fast local loop while building Haxe -> Rust apps:

1. You edit `.hx` files.
2. The watcher recompiles your `.hxml` target.
3. It runs Cargo automatically (`run` or `test`) so you get immediate feedback.

You do not need to know compiler internals to use it.

## Install `watchexec` once

The watcher script uses [`watchexec`](https://github.com/watchexec/watchexec).

Install with either:

- Homebrew: [`brew install watchexec`](https://formulae.brew.sh/formula/watchexec)
- Cargo: [`cargo install watchexec-cli`](https://crates.io/crates/watchexec-cli)

## Quick start

From the repo root:

```bash
npm run dev:watch -- --hxml examples/hello/compile.hxml
```

That runs in `run` mode by default:

- compile Haxe with the selected `.hxml`
- run generated Rust with `cargo run -q`
- repeat on file changes

## Common commands

Run tests on every change:

```bash
npm run dev:watch -- --hxml examples/hello/compile.hxml --mode test
```

Compile only (no `cargo run` / `cargo test`):

```bash
npm run dev:watch -- --hxml examples/hello/compile.hxml --mode build
```

Run one cycle and exit (no watcher required):

```bash
npm run dev:watch -- --hxml examples/hello/compile.hxml --once
```

## Arguments

- `--hxml <path>`: required build target file.
- `--mode <run|build|test>`: per-change action. Default `run`.
- `--watch <path>`: add extra paths to watch (repeatable).
- `--debounce-ms <n>`: delay before rebuild. Default `250`.
- `--once`: run one cycle without starting file watch.
- `--haxe-bin <path>`: override Haxe binary.
- `--cargo-bin <path>`: override Cargo binary.

## Practical tips

- Start with one example or app `.hxml`, then switch to your project target.
- Use `--mode test` in active development for faster feedback on regressions.
- Keep generated output out of your watch roots to avoid loops (the script already ignores common generated folders).

## Related docs

- [Start Here](start-here.md)
- [Workflow (Haxe -> Rust -> native)](workflow.md)
- [Defines reference](defines-reference.md)
