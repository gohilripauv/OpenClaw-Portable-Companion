# OpenClaw Portable Companion 0.2.0

**Portable Codex development with ChatGPT OAuth**

> **Release status:** community preview. This is not an official OpenClaw or
> OpenAI release. The official OpenClaw Companion executable is included
> unchanged and retains its upstream signature; the portable launcher,
> coordinated runtime, and release process are maintained by this project.

## Summary

Version 0.2.0 turns the 0.1.0 portable Companion wrapper into a complete local
Codex development bundle. It packages the official signed OpenClaw Companion
with a portable Node.js runtime, a pinned OpenClaw Gateway, the matched official
`@openclaw/codex` plugin, and that plugin's managed native OpenAI Codex runtime.

The result is a single Windows ZIP that can be extracted and launched without
installing Node.js, OpenClaw, Codex, WSL, a Windows service, or a scheduled task.
Authentication is deliberately limited to ChatGPT/Codex OAuth; this release
does not use an API key as a fallback.

## Why this release exists

The official OpenClaw Companion already publishes signed portable x64 and
ARM64 ZIPs. Those assets provide the Windows UI and expect a compatible local
OpenClaw Gateway. This community bundle keeps that UI unchanged and adds a
coordinated Gateway and Codex runtime beside it.

Choose the official portable Companion when you already operate a Gateway,
want upstream's normal setup/update experience, or require official support.
Choose this bundle when the target Windows account may run approved portable
executables but cannot install the complete local development stack.

See [the full comparison](COMPARISON.md) for the official Companion, the
TechJarves USB launcher, and this project.

## Highlights

### One ZIP, complete local stack

- Packages the official signed OpenClaw Companion `2026.7.1` for x64 and
  ARM64 without modifying its executable.
- Bundles Node.js `24.15.0` and OpenClaw Gateway `2026.8.1-beta.2`; the target
  machine does not run npm or download executable dependencies during setup.
- Does not provision WSL, install a service, create a scheduled task, modify
  `PATH`, or add a registry autorun entry during normal use.
- Redirects Gateway state, Companion/WebView2 data, Codex state, logs,
  credentials, temporary files, and the default workspace into `data\`.

### Native Codex development instead of a generic model route

- Vendors the matched official `@openclaw/codex` `2026.8.1-beta.2` package as
  an OpenClaw bundled extension.
- Includes the exact managed `@openai/codex` `0.147.0` Windows runtime used by
  that plugin; a separately installed Codex CLI is neither needed nor selected.
- Enables the trusted `/codex` command surface and native Codex threads, tool
  continuation, compaction, shell/file execution, and app-server lifecycle.
- Routes `openai/*` agent models through runtime `codex` and fails closed if
  that runtime or plugin is unavailable. It does not silently fall back to the
  generic OpenClaw harness.
- Selects `openai/gpt-5.6-sol` by default while allowing the authenticated
  account's compatible OpenAI agent models to be inspected with
  `/codex models`.

### ChatGPT/Codex OAuth only

- Creates one fixed OpenClaw auth profile: `openai:portable-oauth`.
- Provides browser OAuth and a separate device-code helper for environments
  where a localhost callback is unavailable.
- Restricts OpenAI auth order to the portable OAuth profile.
- Clears inherited `OPENAI_API_KEY` and `CODEX_API_KEY` values from the wrapper
  and all child processes without changing the user's machine-wide settings.
- Rejects API keys embedded in the portable OpenClaw configuration.
- Keeps the native Codex home agent-scoped under the portable folder so an
  unrelated Codex installation cannot be imported silently.

### Safer portable defaults

- Runs the Gateway on `127.0.0.1` with a random 256-bit token; unauthenticated
  Gateway mode is not available through this wrapper.
- Uses Codex guardian execution (`workspace-write` with reviewed approvals)
  rather than unrestricted YOLO execution.
- Applies restricted ACLs to portable credentials and recursively normalizes
  copied state on NTFS/ReFS.
- Refuses silent credential storage on FAT/exFAT unless the operator explicitly
  accepts the warning.
- Ties the exact Gateway process tree to the launcher with a Windows
  kill-on-close job and verifies graceful shutdown and immediate restart.
- Leaves Windows-node screen, camera, location, browser-proxy, and system-run
  capabilities disabled in the generated Companion settings.

## What changed from 0.1.0 (`main`)

| Area | 0.1.0 baseline | 0.2.0 Codex branch |
| --- | --- | --- |
| Agent runtime | Selected an OpenAI model but did not force a runtime | Explicitly requires the official `codex` runtime for `openai/*` |
| Codex plugin | Not packaged | Exact official plugin packaged as a trusted bundled extension |
| Native Codex | Not packaged or version-tested | Managed `@openai/codex` `0.147.0` packaged and executed during validation |
| Failure behavior | Could resolve through OpenClaw's generic harness | Fails closed if Codex is missing, disabled, incompatible, or cannot start |
| Authentication | OpenAI OAuth login, without a fixed exclusive profile | Fixed ChatGPT/Codex OAuth profile and explicit auth order; API-key fallback removed |
| Native state | No dedicated portable Codex home | Agent-scoped `CODEX_HOME` under `data\codex-home` |
| Permissions | OpenClaw defaults | Explicit guardian/workspace-write posture with reviewed approvals |
| User controls | Generic OpenClaw commands | Adds `/codex`, `/codex status`, `/codex models`, and native session behavior |
| Supply-chain record | Gateway/Node/Companion pins and SBOM | Adds exact plugin/native-runtime integrity pins, license, and SBOM entries |
| Regression tests | Gateway auth, lifecycle, integrity, and portable state | Adds plugin provenance, reserved-command registration, native version, OAuth isolation, fail-closed routing, and authenticated restart checks |

## Difference from the official portable Companion

This branch does **not** replace or fork the official UI. It wraps the official
portable asset and adds the pieces required for a self-contained local Codex
stack.

| Capability | Official Companion portable ZIP | This community bundle |
| --- | --- | --- |
| Signed OpenClaw Windows UI | Yes | Yes, copied unchanged from the official ZIP |
| Local Gateway | Must already be available or be configured through upstream setup | Exact compatible Gateway included and launched automatically |
| Node.js/OpenClaw installation | Depends on the chosen Gateway setup | Portable copies included |
| Official Codex plugin and managed runtime | Depends on the connected Gateway | Included, pinned, and preconfigured |
| Authentication policy | Determined by the Gateway/operator | ChatGPT/Codex OAuth only |
| Portable workspace and credentials | Companion data can be portable; Gateway state is separately managed | Companion, Gateway, Codex, workspace, and credentials share one controlled `data\` tree |
| Updates | Upstream updater and official release flow | Coordinated replacement ZIP; in-app updating is suppressed |
| Support | Official OpenClaw project | Community wrapper only |
| Download size | Smaller UI-only asset | Approximately 435 MB on x64 because the complete native stack is included |

The official distribution remains the lower-maintenance and lower-risk choice
for users who can install or operate its expected Gateway. The benefit of this
branch is packaging and policy, not a claim that its UI is better than upstream.

## Security and supply-chain changes

- Every executable archive is pinned by URL and SHA-256 in `versions.json`.
- The Companion's Authenticode signature and expected OpenClaw Foundation
  publisher are checked during build and before launch.
- OpenClaw, `@openclaw/codex`, and `@openai/codex` use exact package versions
  and recorded npm integrity values in the committed lockfile.
- The build fails on moderate-or-higher npm advisories and produces a
  CycloneDX SBOM.
- Every immutable file in the assembled bundle is cataloged; launch rejects
  changed files, unexpected files, and reparse points outside mutable `data\`.
- All six findings from the pre-publication wrapper security review remain
  remediated. The Codex branch adds focused regression checks but is not an
  independent audit of the upstream OpenClaw or OpenAI codebases.

The beta Gateway was selected deliberately. At the release decision point,
the locked production tree for `2026.8.1-beta.2` reported zero known npm
vulnerabilities, while stable `2026.7.1-2` reported four high and six moderate
advisories. This is a point-in-time dependency result, not proof that the beta
is vulnerability-free.

## Validation performed

The final x64 artifact passed the automated release gate on Windows:

- PowerShell syntax, dependency pins, lockfile integrity, and launcher-policy
  checks.
- Clean extraction, unsafe ZIP-path rejection, one-root layout, and SBOM
  validation.
- Full immutable-tree rehash plus deliberate tamper detection.
- Companion signature and portable NTFS ACL checks.
- Native `codex-cli 0.147.0` execution.
- Official plugin inventory and trusted reserved `/codex` registration.
- OAuth-only environment isolation and rejection of ambient Codex auth import.
- Loopback Gateway start, authenticated RPC readiness, wrong-token rejection,
  graceful shutdown, and authenticated immediate restart.
- Dependency audit with zero known vulnerabilities in the locked production
  graph at build time.

The x64 release candidate built locally was approximately 435 MB and passed
this gate. The GitHub release workflow rebuilds and retests both architectures
from the release tag. For published downloads, the authoritative digest is the
matching `SHA256SUMS-x64.txt` or `SHA256SUMS-arm64.txt` release asset; build
timestamps make local and CI ZIP hashes different even when their source and
payload versions match.

The following still require manual release acceptance before removing the
preview label: interactive OAuth with a real account, a real Codex coding turn
through the Companion UI, credential persistence after restart, a clean Windows
VM with no development tools, testing under representative managed-device
policies, and native ARM64 release validation.

## Version matrix

| Component | Version | Packaging |
| --- | --- | --- |
| Portable wrapper | `0.2.0` | Community project |
| Official OpenClaw Companion | `2026.7.1` | Official signed upstream ZIP, unchanged |
| OpenClaw Gateway | `2026.8.1-beta.2` | Exact lockfile dependency |
| Official `@openclaw/codex` plugin | `2026.8.1-beta.2` | Vendored unchanged as a bundled extension |
| Managed OpenAI Codex | `0.147.0` | Exact plugin dependency |
| Node.js | `24.15.0` | Official portable archive |

## Upgrade notes for 0.1.0 users

The 0.2.0 runtime policy is intentionally stricter than 0.1.0. Do not overwrite
the old executable tree in place.

1. Exit the Companion and confirm the old Gateway has stopped.
2. Back up `data\workspace` and any other portable data you need.
3. Extract 0.2.0 into a new NTFS/ReFS folder.
4. Copy only authorized workspace content into the new `data\workspace`.
5. Run `Start-OpenClaw.bat` and complete ChatGPT/Codex OAuth again.
6. Confirm `/status` reports `Runtime: OpenAI Codex`, then run
   `/codex status`.

Do not copy the 0.1.0 `data\config` into 0.2.0: it does not contain the required
fail-closed Codex policy. Do not distribute or email a folder after sign-in;
its `data\` tree contains credentials and potentially sensitive work.

## Known limitations

- This is a community wrapper and its PowerShell/batch launchers are not code
  signed, although the official Companion executable is.
- The Gateway is a beta build. Organizations that prohibit beta software
  should wait for a suitable stable OpenClaw release.
- “No installer” does not bypass AppLocker, WDAC, Defender/EDR, proxy, DLP,
  PowerShell, removable-media, or AI-use policy.
- OAuth and model use still require network access to permitted services.
- The x64 ZIP exceeds ordinary email attachment limits; use an approved
  file-transfer location or send an approved download link.
- This provides the official Codex runtime inside OpenClaw. It is not the same
  UI or every feature of the official ChatGPT/Codex desktop application.
- Only the clean release ZIP is safe to redistribute. A used portable folder
  may contain OAuth credentials, chat state, logs, and workspace files.

## References

- [Official OpenClaw Companion v2026.7.1 release](https://github.com/openclaw/openclaw-windows-node/releases/tag/v2026.7.1)
- [Official OpenClaw Codex harness guide](https://docs.openclaw.ai/plugins/codex-harness)
- [Official Codex harness reference](https://docs.openclaw.ai/plugins/codex-harness-reference)
- [Security review](SECURITY-REVIEW.md)
- [Threat model](THREAT-MODEL.md)
