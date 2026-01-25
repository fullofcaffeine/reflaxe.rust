# reflaxe.rust basic template

This is a minimal starter layout for a **Haxe → Rust** project using `reflaxe.rust`.

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

```bash
haxe compile.hxml
./out/target/debug/hx_app
```

## Notes

- `reflaxe.rust` runs `cargo build` automatically after codegen (opt-out: `-D rust_codegen_only`).
- Use `-D rust_release` for release builds.
