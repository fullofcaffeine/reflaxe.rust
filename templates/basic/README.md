# reflaxe.rust basic template

This is a minimal starter layout for a **Haxe → Rust** project using `reflaxe.rust`.

From this repository, you can scaffold this template directly with:

```bash
npm run dev:new-project -- ./my_haxe_rust_app
```

## Setup

From this folder:

```bash
npx lix scope create

# Install a specific release tag (recommended)
REFLAXE_RUST_TAG="$(curl -fsSL https://api.github.com/repos/fullofcaffeine/reflaxe.rust/releases/latest | sed -n 's/.*\"tag_name\":[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' | head -n 1)"
npx lix install "github:fullofcaffeine/reflaxe.rust#${REFLAXE_RUST_TAG}"

npx lix download
npx lix download haxe 4.3.7
npx lix use haxe 4.3.7
```

## Build

The template ships explicit task HXMLs:

- `compile.build.hxml` -> debug compile only (`cargo build`)
- `compile.hxml` -> debug compile+run (`cargo run`) default
- `compile.run.hxml` -> explicit debug compile+run (`cargo run`)
- `compile.release.hxml` -> release compile only (`cargo build --release`)
- `compile.release.run.hxml` -> release compile+run (`cargo run --release`)

```bash
haxe compile.build.hxml
haxe compile.hxml
haxe compile.release.hxml
haxe compile.release.run.hxml
```

## Notes

- `reflaxe.rust` runs `cargo build` automatically after codegen (opt-out: `-D rust_codegen_only`).
- The crate name defaults to `hx_app`; update `-D rust_crate=...` in `compile*.hxml` if needed.
- Generated binaries are at:
  - `out/target/debug/hx_app`
  - `out_release/target/release/hx_app`
