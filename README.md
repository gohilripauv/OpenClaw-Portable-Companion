# OpenClaw Portable Companion

An unofficial, no-installer Windows bundle that combines the **official signed
OpenClaw Companion**, a portable Node.js runtime, and a pinned OpenClaw Gateway.
Extract one ZIP, keep it in one folder, and run `Start-OpenClaw.bat`.

This repository is a packaging and lifecycle wrapper. It is deliberately **not
a fork of the official Companion source**: upstream already publishes portable
x64 and ARM64 ZIPs, so keeping that signed application unchanged reduces both
maintenance and trust risk.

## What you get

- No MSI/MSIX installation and no administrator prompt from this wrapper.
- No WSL provisioning, service installation, scheduled task, PATH edit, or
  registry autorun during normal use.
- Official Companion files with their Authenticode signature preserved.
- Exact version pins and SHA-256 checks for every downloaded executable archive.
- A lockfile-pinned OpenClaw dependency graph; no `openclaw@latest` download on
  the user's machine.
- A CycloneDX software bill of materials (SBOM) in each release bundle.
- Gateway token authentication on `127.0.0.1` only.
- State, workspaces, logs, WebView2 data, and credentials redirected to `data\`
  beside the app.
- Gateway lifecycle tied to the launcher with a Windows kill-on-close job, plus
  exact-PID cleanup during normal exit.

## Download and run

1. Download the x64 or ARM64 ZIP from this repository's Releases page and the
   matching `SHA256SUMS` file.
2. Verify it in PowerShell:

   ```powershell
   Get-FileHash .\OpenClaw-Portable-Companion-0.1.0-win-x64.zip -Algorithm SHA256
   ```

3. Extract the whole ZIP to a writable **NTFS or ReFS** folder. For removable
   media, NTFS with BitLocker To Go is strongly recommended.
4. Double-click `Start-OpenClaw.bat`. On first run it offers to open the
   official ChatGPT/Codex OAuth flow.
5. If a corporate browser blocks the localhost callback, run
   `Configure-OpenAI-Device-Code.bat` and follow the device-code instructions.
6. When finished, choose **Exit** from the Companion tray icon. The launcher
   stops the Gateway and returns.

The portable data is the `data\` directory. To move the application, exit it
fully and copy the entire extracted folder. To reset it, first back up anything
you need from `data\workspace`, then remove `data\` while the app is stopped.

## Requirements and honest limits

- Windows 10 20H2 or later, or Windows 11.
- Microsoft Edge WebView2 Runtime. It is present on supported Windows 11 and
  most managed Windows 10 devices, but this project does not install it.
- The organization and device owner must permit executable code from the chosen
  folder. “No installer” does not bypass AppLocker, WDAC, endpoint protection,
  network policy, data-loss prevention, or your employer's AI rules.
- ChatGPT web approval does not automatically authorize a third-party agent to
  read local files or execute tools. Confirm that broader use with IT/security.
- The Companion stores its shared Gateway token in `data\companion\gateways.json`;
  OpenClaw stores provider credentials under `data\openclaw-state`. The wrapper
  restricts ACLs on NTFS/ReFS, but credentials on FAT/exFAT cannot be adequately
  protected and require an explicit warning override.
- This is portable application state, not “zero host trace.” Windows may retain
  normal OS evidence such as Defender/SmartScreen history, event logs, DNS/cache
  data, jump lists, or crash records.
- Do not enable the Companion's **Start with Windows** option. It is unnecessary
  for this package and would create host-level startup state.
- The official Companion's in-app updater is suppressed because the data-dir
  override identifies this as an isolated instance. Upgrade by downloading a
  coordinated release of this bundle.
- Release 0.1.0 pairs the latest signed Companion (`2026.7.1`) with the newer
  official Gateway (`2026.8.1-beta.2`). The Gateway is a beta because the
  current stable package has known vulnerable transitive dependencies; see the
  release notes. If beta software is outside your organization's policy, wait
  for an updated stable OpenClaw release.

## Security defaults

The Gateway is always launched with `--bind loopback --auth token`. A random
256-bit token is generated locally and never placed on a command line. If the
default port is occupied, the launcher fails closed instead of killing or
reusing an unidentified process. Every shipped immutable file is cataloged and
rehashed at startup, unexpected files in the executable trees are rejected, and
the Companion publisher signature is checked before execution. This same-folder
catalog is defense in depth; verification of the published ZIP checksum remains
the trust anchor against complete folder replacement.

The initial Companion settings disable Windows-node capabilities (screen,
camera, location, browser proxy, and system execution). OpenClaw itself remains
an agent capable of reading and changing files in its configured workspace.
Only place work there that the tool is authorized to access.

See [SECURITY.md](SECURITY.md) and [the threat model](docs/THREAT-MODEL.md).

## Build it yourself

Run from Windows PowerShell 5.1 or PowerShell 7 on a machine matching the target
architecture:

```powershell
.\scripts\Test-Portable.ps1
.\scripts\Build-Portable.ps1 -Architecture x64
```

The build downloads only URLs recorded in `versions.json`, verifies their
SHA-256 values before extraction, verifies the Companion's OpenClaw Foundation
signature, installs from `gateway/package-lock.json`, fails on moderate-or-higher
npm advisories, runs CLI smoke tests, and writes a release ZIP, checksum, and
CycloneDX SBOM under `dist\`.

ARM64 artifacts are assembled on GitHub's native `windows-11-arm` runner so
native optional dependencies and install scripts see the correct architecture.
The manual release workflow creates a draft first and publishes it only after
both architecture builds succeed. Build jobs have read-only repository access
and no persisted Git credential; a separate job uploads the verified artifacts.

## Updating upstream pins

Do not replace version strings alone. For each update:

1. Review the official Companion and OpenClaw release notes.
2. Update both architecture URLs and verified archive digests in
   `versions.json`.
3. Update `gateway/package.json`, regenerate `gateway/package-lock.json` using
   npm from the pinned Node archive, and confirm the OpenClaw package integrity
   matches the npm registry metadata. Validate the graph with `npm sbom`; do not
   regenerate the lock with an arbitrary older host npm.
4. Run tests and a full x64 build locally; let the release workflow build ARM64
   on native hardware.
5. Test first-run OAuth, authenticated Companion connection, chat, movement of
   the extracted folder, port-conflict failure, and Gateway cleanup.

See [the design decision](docs/DECISION.md) for the comparison with the earlier
USB launcher and a source fork, and [the pre-release security review](docs/SECURITY-REVIEW.md)
for the issues fixed before the first public release.

## Trademark and support

This is an unofficial community project, not endorsed by OpenClaw Foundation,
OpenAI, Microsoft, or Node.js. File wrapper-specific issues here; reproduce
upstream application defects with the official distribution before reporting
them to the OpenClaw projects.

MIT licensed. Bundled components retain their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
