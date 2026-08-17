# Why this is a wrapper, not a fork

Three approaches were evaluated in August 2026.

| Approach | What it provides | Maintenance and security result |
| --- | --- | --- |
| `techjarves/OpenClaw-USB-Portable` | Portable Node.js plus OpenClaw CLI/Gateway/TUI/dashboard | Useful prototype, but not the official Companion. The reviewed revision downloaded mutable/unverified executable dependencies, disabled Gateway authentication, left the Gateway detached, and had path-injection edge cases. |
| Fork `openclaw/openclaw-windows-node` | Full control over the Windows Companion source | Legally possible under MIT, but unnecessary for portability and costly to keep aligned with a fast-moving signed upstream. A fork would also lose upstream's signature unless a new signing identity and release process were maintained. |
| Package the official portable Companion | Upstream-signed UI plus a local portable Gateway/runtime | Selected. It preserves the trust boundary, keeps the delta small, and lets this project focus on version pinning, local state, auth, plugin packaging, and process lifecycle. |

The official Companion already publishes portable x64 and ARM64 ZIPs and honors
`OPENCLAW_TRAY_DATA_DIR` for isolated local/roaming application data. The
wrapper uses that supported code path, redirects OpenClaw's own state through
its documented environment variables, and starts a separately pinned Gateway.
The official `@openclaw/codex` package and its exact managed Codex runtime are
vendored as a bundled extension during release assembly. This is needed because
a mere load path is treated as external and cannot own OpenClaw's reserved
`/codex` command; the plugin code itself remains unchanged.

The official UI is expanded unchanged into `app\`. This repository owns only
the wrapper scripts, assembly metadata, release automation, security defaults,
and documentation. If upstream later publishes an official combined portable
Gateway + Companion bundle with equivalent lifecycle and state isolation, this
project should retire in favor of it.
