# ADR — No Apple Developer ID (current phase)

## Status
Accepted — current phase. Revisit before public distribution.

<!-- UPDATE 2026-07-13: the app went fully free and the auth stack was removed (see decisions/fully-free-server-decommission.md). Compensations #3 (OAuth state parameter) and #4 (PKCE verifier in Keychain) below are now MOOT — `Sources/BlikShared/Auth/OAuthClient.swift` and `KeychainStore.swift` were deleted. Compensations #1 (ClientAuthorization path-whitelist) and #2 (root-only PKG download dir) are still live and unchanged. -->


## Context
blik is built and distributed without an Apple Developer ID. This affects
multiple security mechanisms that would normally rely on code-signing:

- PKG installer is **unsigned** → `pkgutil --check-signature` returns
  `Status: no signature`. The auto-updater (`Sources/BlikHelper/UpdateChecker.swift`)
  cannot verify download integrity via Apple's signature chain.
- App binaries are unsigned → XPC helper cannot use
  `SecCodeCheckValidity` with a requirement string anchored on `subject.OU`
  (team-id). Standard recipe for privileged-helper-auth is unavailable.
- Notarization not applicable.

## Decision
Operate without code-signing for the current phase. Compensate via:

1. **XPC client authorization by path-whitelist** —
   `Sources/BlikHelper/ClientAuthorization.swift` resolves connecting client's
   PID → executable path via `proc_pidpath` and matches against an explicit
   allowlist of installed binary paths (`/Applications/Blik.app/...`,
   `/usr/local/bin/blik`). This is *not* cryptographic protection — a root
   process can recreate any path — but it stops user-mode malware from
   trivially invoking `setFanSpeedPreset`, `performUpdate`, `uninstallAll`.
2. **PKG download into root-only directory** —
   `/var/db/blik/updates/` with mode 0700 (created by the helper).
   Eliminates the TOCTOU window the previous `/tmp/blik-update.pkg`
   download path left open. We still can't verify the PKG itself (S0-2 in
   the security plan), but the file at least cannot be swapped by a
   user-mode process between download and `installer -pkg`.
3. **OAuth state parameter** —
   `Sources/BlikShared/Auth/OAuthClient.swift` now generates and verifies a
   32-byte `state` parameter on every authorization flow. Defends against
   code-injection (RFC 6749 §10.12).
4. **PKCE verifier in Keychain (not UserDefaults)** —
   verifier was readable by any process under the same UID. Now lives in
   Keychain with the rest of the auth material.

## Consequences

Positive: dev workflow stays simple (`scripts/build.sh <ver>` produces a PKG
without signing). No certificate management overhead during the bootstrap
phase.

Negative:
- Path-whitelist isn't cryptographic; **assume blik runs only on the
  developer's own machines** in this phase. Do not ship to third parties.
- Auto-update channel inherits trust of GitHub release URL only. If a
  GitHub release is compromised, no client-side check stops a malicious PKG.

Trackers/reminders to revisit:
- When Developer ID is obtained:
  - Replace `ClientAuthorization.isAuthorized(pid:)` with a `SecCode`-based
    check using requirement `anchor apple generic and identifier "com.blik.app"
    and certificate leaf[subject.OU] = "<TEAM_ID>"`.
  - Sign PKG; enable `pkgutil --check-signature` before `installer -pkg`.
  - Re-evaluate `decisions/sandbox-off.md` (sandbox becomes practical).

## Related
- `Sources/BlikHelper/ClientAuthorization.swift`
- `Sources/BlikHelper/UpdateChecker.swift`
- `Sources/BlikShared/Auth/OAuthClient.swift`
- `Sources/BlikShared/Auth/KeychainStore.swift`
- `decisions/sandbox-off.md`
