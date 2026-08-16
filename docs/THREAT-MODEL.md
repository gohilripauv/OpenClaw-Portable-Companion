# Threat model

## Assets

- ChatGPT/Codex OAuth credentials and provider API keys.
- The local Gateway shared token and paired-device identities.
- Source code and documents placed in the portable workspace.
- Prompts, responses, logs, sessions, and generated artifacts.

## Trust boundaries

The release consists of this wrapper, the official signed Companion, the
official Node.js runtime, OpenClaw and its locked npm dependencies, Windows,
WebView2, the user's browser, model providers, and any agent tools enabled by
the user. A checksum verifies a release file but does not make every upstream
dependency risk-free.

## Defended scenarios

- Network substitution during assembly: archive digests and npm integrity are
  checked before release output is accepted.
- Local network access to the Gateway: it binds only to loopback and requires a
  random token.
- Command injection through a folder containing spaces or apostrophes: native
  processes receive argument arrays or Win32-quoted arguments; no path is
  interpolated into a nested PowerShell command.
- Accidental use of an unrelated local process: an occupied Gateway port causes
  failure, not process termination or unauthenticated reuse.
- Orphaned Gateway after normal or abnormal launcher exit: the wrapper records
  the exact process and attaches it to a kill-on-close Windows job object.
- Ambient access to credentials: the `data\` ACL is reduced to the current user,
  SYSTEM, and local Administrators on NTFS/ReFS.

## Residual risks

- An attacker who can modify the wrapper or all release files can also alter the
  verification logic. Verify the published ZIP checksum before extraction.
- Local Administrators and sufficiently privileged endpoint software can read
  or alter portable state.
- FAT/exFAT and many network filesystems do not preserve the required ACLs.
- A malicious or compromised model/tool/plugin can misuse capabilities the user
  grants. Portable packaging does not sandbox OpenClaw.
- OAuth, DNS, proxy, endpoint-security, Windows telemetry, crash dumps, and
  browser behavior can leave host traces outside the portable directory.
- Hard power loss or forced termination can leave application-level recovery
  files, though the OS closes the job object and terminates the Gateway.
- The unmodified Companion exposes a Start-with-Windows control; users must not
  enable it when they require a no-install/no-persistence workflow.

## Non-goals

- Bypassing administrator controls, AppLocker, WDAC, antivirus, proxy rules, or
  organizational policy.
- Hiding execution from device administrators.
- Providing anonymity or forensic non-persistence.
- Making a shared USB stick safe for multiple untrusted users.
