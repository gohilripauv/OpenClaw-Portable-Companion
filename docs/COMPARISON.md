# Portable OpenClaw options compared

This project is an **unofficial community distribution**. It does not contain
a forked or modified OpenClaw Companion executable. It packages the official
signed Companion unchanged and supplies a coordinated portable Gateway and
Codex development runtime around it.

The projects below solve different portability problems. None is universally
better; the right choice depends on whether you need only a portable UI, a
cross-platform bootstrap workspace, or a preassembled Windows Codex stack.

## At a glance

| | Official OpenClaw Companion portable ZIP | TechJarves OpenClaw USB Portable | OpenClaw Portable Companion 0.2.0 |
| --- | --- | --- | --- |
| Publisher | OpenClaw upstream | Community | Community |
| Operating systems | Windows x64 and ARM64 | Windows, Linux, and macOS | Windows x64 and ARM64 release design |
| Main interface | Official signed Companion | CLI/TUI and dashboard launcher | Official signed Companion, unchanged |
| Gateway | Expected separately | Installed project-locally on first run | Exact Gateway prepackaged and lifecycle-managed |
| Node.js | Determined by Gateway setup | Downloaded portably on first run | Exact portable runtime prepackaged |
| Codex development harness | Determined by connected Gateway | Not fixed by the public launcher description | Official plugin and exact managed Codex runtime included |
| OpenAI authentication | Determined by Gateway/operator | Provider setup menu | ChatGPT/Codex OAuth only; API-key fallback disabled |
| Runtime downloads on target | Companion still needs a Gateway | First run downloads runtime and installs OpenClaw | No executable dependency download during setup |
| State model | Companion state; Gateway state managed separately | Shared portable `data/` workspace | Companion, Gateway, Codex, credentials, logs, and workspace under `data\` |
| Integrity evidence | Official signed app and release assets | Depends on launcher/revision | Upstream archive hashes, signature check, lockfile integrities, complete file catalog, checksum, and SBOM |
| Updates | Official updater/release flow | Launcher-managed setup | Replace with a coordinated community release ZIP |
| Approximate x64 size | Smaller UI-focused download | Small source checkout; dependencies arrive during setup | About 435 MB, with dependencies already included |
| Best fit | Users who already have or can configure a supported Gateway | Cross-platform users who accept first-run bootstrap | Managed Windows users permitted to run a self-contained approved ZIP |

Sources: the [official Companion v2026.7.1 release](https://github.com/openclaw/openclaw-windows-node/releases/tag/v2026.7.1),
the [TechJarves project README](https://github.com/techjarves/OpenClaw-USB-Portable),
and the [official Codex harness guide](https://docs.openclaw.ai/plugins/codex-harness).
The table describes those pages and this repository as reviewed in August 2026;
upstream behavior may change.

## Benefits of this Codex branch

### A complete development runtime, not only a portable UI

The official Companion portable asset is already the best source for the
signed Windows UI. Its release requirements include a running local Gateway.
This project adds the compatible Gateway, Node.js, provider configuration,
Codex plugin, and managed Codex binary, then starts and stops them as one
portable application.

### Native Codex semantics

Selecting an OpenAI model is not the same as running the Codex harness. The
official `codex` plugin hands the low-level agent loop to Codex app-server,
including native thread resume, tool continuation, compaction, and execution.
This branch packages that plugin and explicitly binds `openai/*` agent models
to runtime `codex`.

If the plugin or managed app-server cannot start, the route fails rather than
silently changing behavior through OpenClaw's generic harness.

### Subscription OAuth is an enforced product decision

The wrapper creates a fixed ChatGPT/Codex OAuth profile and clears inherited
OpenAI API-key variables for its child processes. This makes the intended
billing/authentication path reviewable and repeatable. It does not delete or
modify API keys belonging to other applications.

Users who need API-billed provider routes or several model providers should
use normal OpenClaw setup instead; this bundle intentionally does not support
that use case.

### Predictable target-machine setup

All executable dependencies are assembled before release. The target user
extracts the ZIP, authenticates, and launches it. They do not run npm, install
Node.js or Codex, provision WSL, create a service, or depend on a mutable
`latest` download during first run.

This is useful where software installation is restricted but approved portable
executables are allowed. It is not a way around endpoint policy: AppLocker,
WDAC, Defender/EDR, proxies, DLP, PowerShell policy, and organizational AI rules
still apply.

### Coordinated security and provenance

The official Companion remains signed by upstream. The community-owned layer
adds exact archive hashes, package-integrity pins, an npm lockfile, a CycloneDX
SBOM, a complete immutable-file catalog, loopback token authentication,
portable credential ACLs, occupied-port failure, and exact-process cleanup.

These controls reduce accidental drift and make substitution easier to detect.
They do not give this project OpenClaw's official support or signing identity,
and they do not constitute an independent audit of upstream dependencies.

## Reasons to choose the official Companion instead

- You can install or operate a supported Gateway normally.
- You want the smallest download and do not need a bundled Codex runtime.
- You need upstream's standard setup, updater, support path, and release cadence.
- Your organization permits only official packages or prohibits beta
  dependencies and unsigned community launchers.
- You need Companion capabilities that this wrapper disables by default, such
  as Windows-node screen, camera, location, browser proxy, or system execution.

The official release should be the default choice whenever it already meets
the deployment requirement. This wrapper is valuable only for the narrower
portable, no-installer, OAuth-only Codex scenario.

## Reasons to choose the TechJarves launcher instead

- You need Windows, Linux, and macOS from one portable workspace.
- A first-run download and project-local OpenClaw installation are acceptable.
- You prefer the CLI/TUI/dashboard workflow over the official Windows
  Companion.
- You need provider flexibility rather than a deliberately OAuth-only OpenAI
  Codex configuration.

This project instead optimizes for a preassembled Windows artifact, the signed
official Companion UI, deterministic dependency pins, and a fixed Codex policy.

## Important tradeoffs

- The complete x64 bundle is approximately 435 MB.
- The pinned Gateway is `2026.8.1-beta.2`; this release is therefore a preview.
- Community launcher scripts are not code signed.
- Updates require a new coordinated bundle instead of mixing independently
  updated Companion, Gateway, plugin, and Codex versions.
- A used portable folder contains sensitive state. Only a clean release ZIP
  should be uploaded, emailed, or redistributed.
- The OpenClaw Companion experience is not identical to the official
  ChatGPT/Codex desktop application.

For version-specific changes, validation evidence, and remaining manual tests,
read the [0.2.0 release notes](RELEASE_NOTES.md).

