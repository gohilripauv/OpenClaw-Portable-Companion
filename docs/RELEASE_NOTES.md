# OpenClaw Portable Companion 0.2.0

OAuth-only Codex development preview.

- Packages the official signed OpenClaw Companion 2026.7.1 for x64 and ARM64.
- Bundles Node.js 24.15.0 and OpenClaw 2026.8.1-beta.2 from exact verified pins.
- Vendors the matched official `@openclaw/codex` 2026.8.1-beta.2 plugin into
  OpenClaw's bundled-extension tree, with its managed OpenAI Codex 0.147.0
  Windows runtime. This enables the native `/codex` command surface without a
  target-machine plugin installation.
- Requires `openai/*` agent models to use the Codex runtime and fails closed
  instead of silently reverting to the generic OpenClaw harness.
- Uses ChatGPT/Codex OAuth only through the fixed `openai:portable-oauth`
  profile. Ambient `OPENAI_API_KEY` and `CODEX_API_KEY` values are cleared for
  child processes and are not billing fallbacks.
- Uses Codex guardian permissions (`workspace-write`, reviewed approvals) and
  isolated agent-scoped native state inside the portable folder.
- Uses the official beta Gateway deliberately: the stable `2026.7.1-2` package
  currently reports 4 high and 6 moderate npm advisories, while this beta's
  locked production dependency tree reports zero known npm vulnerabilities at
  release time. The Companion itself remains the latest signed stable release.
- Redirects state to the extracted folder without WSL, services, PATH changes,
  or an installer.
- Requires loopback-only Gateway token authentication.
- Stops the exact Gateway process tree when the Companion exits.
- Adds first-run ChatGPT/Codex OAuth and device-code helpers.
- Includes a CycloneDX SBOM for independent dependency review.
- Remediates all six findings from the pre-publication wrapper scan: trusted
  PowerShell selection, mandatory complete bundle cataloging, direct OAuth-path
  verification, recursive copied-state ACL repair, least-privilege release jobs,
  and fail-closed Gateway containment.

Read the README's requirements and security limitations before use on managed
or removable devices.
