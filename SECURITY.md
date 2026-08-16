# Security policy

## Supported versions

Only the newest release of this wrapper is supported. Upstream OpenClaw,
Companion, Node.js, and transitive dependency vulnerabilities are normally
handled by producing a new coordinated bundle rather than patching binaries.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository
when available. Do not include OAuth tokens, Gateway tokens, `gateways.json`,
provider databases, logs containing prompts, or proprietary work files in a
public issue.

Include the wrapper version, architecture, Windows version, exact reproduction
steps, and whether the issue also occurs with the corresponding official
OpenClaw component. Redacted logs are welcome.

## Trust and release process

- Official Companion and Node.js archives are pinned by SHA-256 in
  `versions.json`.
- The Companion's Authenticode publisher is checked during assembly and launch.
- OpenClaw is an exact npm dependency with a committed lockfile and recorded npm
  integrity value.
- Release builds fail on moderate-or-higher npm advisories and emit a CycloneDX
  SBOM. An audit result is a point-in-time signal, not proof of safety.
- Release ZIP SHA-256 values are published alongside every release.
- Release assembly runs on native x64 and ARM64 Windows runners.
- Build jobs have read-only repository permission and do not retain checkout
  credentials while npm lifecycle scripts execute.
- The runtime catalog covers every shipped immutable file and fails closed, but
  remains a same-folder defense-in-depth control rather than a signed trust root.

These controls make substitution detectable; they do not turn this community
wrapper into an official OpenClaw build. Users should review source, verify the
download checksum, and follow their organization's endpoint policy.

The initial wrapper underwent a complete 26-file standard security review before
publication. See `docs/SECURITY-REVIEW.md` for its remediation record.
