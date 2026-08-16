# Pre-release security review

The initial wrapper candidate was reviewed with a complete, offline Codex
Security Standard scan of all 26 tracked files at commit `9d5e6ed`. Scan ID:
`676bf4d1-eed2-4fbd-8587-62773c71e98a`.

The scan reported five high-severity findings and one low-severity finding. All
six were remediated before the first public release:

| Finding | Resolution |
| --- | --- |
| Batch launchers searched the writable current directory for `powershell.exe` | Every launcher now selects the absolute Windows system PowerShell path and fails if it is unavailable. |
| Runtime integrity checking was optional and covered only selected files | The catalog is mandatory, covers every shipped immutable file, and rejects unexpected files and reparse points outside mutable `data\`. |
| Standalone OAuth configuration skipped integrity verification | Both OAuth entry points now require the same bundle catalog verification before executing Node or OpenClaw. |
| Copied state could retain permissive explicit child ACLs | NTFS/ReFS initialization recursively normalizes descendant ACLs without following reparse targets, then reapplies and verifies the restricted root policy. |
| npm lifecycle code ran with a persisted repository-write credential | Release builds now have read-only permission and `persist-credentials: false`; a separate pinned-artifact job owns release upload. |
| Gateway startup continued when kill-on-close containment failed | Containment creation and assignment are mandatory; either failure aborts startup and exact-process cleanup runs. |

The review also confirmed exact upstream pins and hashes, lockfile integrity,
loopback-only token authentication, wrong-token rejection, occupied-port failure,
graceful shutdown, no wrapper-installed autorun/service, and guarded archive
cleanup. Upstream OpenClaw and Companion internals were dependencies rather than
in-repository source and were not part of this wrapper scan.

The catalog is intentionally described as defense in depth: a party able to
replace the wrapper, catalog, and payload together can replace the verifier too.
Users should verify the release checksum after download and again after the
portable media has been outside trusted custody.
