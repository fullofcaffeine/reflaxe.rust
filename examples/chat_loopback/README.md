# chat_loopback

Flagship cross-profile chat example (`portable`, `idiomatic`, `rusty`, `metal`).

## What It Demonstrates

- One app scenario implemented across all compiler profiles.
- Typed runtime boundary (`ChatRuntime`) with local and network-backed flows.
- Interactive TUI UX plus deterministic headless CI test mode.
- In-frame diagnostics (`diag stream`) so transport/activity signals stay inside the TUI.
- Channel-scoped timeline rendering (`#ops`, `#compiler`, `#shiproom`, `#nightwatch`) so each room has its own feed.
- Presence-driven activity log (`online` / `offline`) shown in its own TUI frame.
- Momentum celebration effect: each room tracks momentum independently; hitting `100` triggers a temporary full-frame center-origin particle burst (colorized ASCII particles, emoji headline when enabled) and resets that room’s momentum so it can be earned again.
- Realtime history-sync behavior that imports new messages once (no repeated full-history spam lines).
- Presence heartbeats + timeout pruning so closed instances disappear from the operator list automatically.

## Default Networking Behavior (Interactive Builds)

When you run the normal (non-`.ci`) build:

1. The app tries to connect to `127.0.0.1:7000`.
2. If no room exists yet, it auto-starts a local host room and joins it.
3. Later instances on the same machine auto-join that same room.

This gives a shared multi-instance chat experience by default.

Note: this is a localhost room-host topology (one host + many clients), not full mesh peer-to-peer.

## Quick Start (Two Instances, Same Room)

Terminal 1:

```bash
cd examples/chat_loopback
npx haxe compile.portable.hxml
(cd out_portable && cargo run -q)
```

Terminal 2:

```bash
cd examples/chat_loopback/out_portable
cargo run -q
```

Each instance gets an auto-generated funny name. Presence updates are automatic; `/history` is still available for manual refresh.

## Cargo Task Driver

Use the repo cargo alias with flags instead of adding many task HXML files:

```bash
cargo hx --example chat_loopback --profile portable --action run
cargo hx --example chat_loopback --profile idiomatic --action run
cargo hx --example chat_loopback --profile portable --ci --action test
cargo hx --example chat_loopback --profile metal --action build --release

# when you're already inside examples/chat_loopback:
# cargo hx --profile portable --action run
```

This keeps profile selection in existing `compile.<profile>.hxml` files while build/run/test behavior is selected via cargo flags.

## Key Bindings

- `Tab` cycles channels.
- `Ctrl+H` toggles the help modal.
- `?` is regular text now (it does not open help by itself).
- `Ctrl+C` or `q` exits.

## Explicit Modes

- `--server [port]`
  - Start a dedicated shared room host.
- `--connect <host:port|port>`
  - Connect as a client only.
  - Fails with an explicit error if the endpoint is unreachable.
- `--local`
  - Force fully local single-process runtime (no shared network room).

## Server Diagnostics

Server connect/disconnect diagnostics are disabled by default so background socket logs do not corrupt the TUI frame.

- Enable them only when debugging transport behavior: `-D chat_server_logs`.

## CI / Headless Note

`compile.*.ci.hxml` defines `chat_tui_headless` for deterministic CI behavior.

In headless mode, the app intentionally does not auto-host and exits quickly after a bounded tick window.
Use non-`.ci` builds for real interactive multi-instance chat.
