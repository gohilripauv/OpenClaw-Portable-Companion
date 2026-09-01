# Repository instructions

## Purpose and layout

This repository builds a security-sensitive portable Windows wrapper around
the signed OpenClaw Companion, pinned Gateway dependencies, and the official
Codex harness. Launcher and lifecycle code is under `scripts/`, dependency pins
under `gateway/` and `versions.json`, security and design records under `docs/`,
and license material under `licenses/`.

## Working rules

- Preserve the official Companion signature; this repository is not its source
  fork.
- Keep Gateway, Node, plugin, and Codex versions and integrity metadata pinned.
  Never replace a version without updating and validating its URL, digest,
  lockfile, notices, and release documentation.
- OAuth is the only supported OpenAI authentication route. Do not introduce an
  API-key fallback or print tokens, credentials, local state, or inherited
  secrets.
- Preserve loopback-only binding, token authentication, port-conflict
  fail-closed behavior, integrity catalogs, bounded cleanup, and restrictive
  portable-state ACLs.
- Generated `data/`, `dist/`, downloaded runtimes, credentials, and build
  products stay out of Git.

## Validate

Run on Windows PowerShell from the repository root:

```powershell
.\scripts\Test-Portable.ps1
.\scripts\Build-Portable.ps1 -Architecture x64
```

For documentation-only changes, `Test-Portable.ps1` is the minimum gate. A
release change also requires a completed x64 bundle, ZIP verification, and the
native ARM64 GitHub workflow. Update `README.md`, security/release records, the
SBOM inputs, and third-party notices whenever their claims change.
