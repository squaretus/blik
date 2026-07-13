# ADR — App Sandbox is off (by design, current phase)

## Status
Accepted — current phase (no Apple Developer ID). Revisit when distribution moves
to App Store or signed distribution.

## Context
`BlikApp` (`Sources/BlikApp`) and `BlikMenuBar` (`Sources/BlikMenuBar`) ship
without the `com.apple.security.app-sandbox` entitlement. Standard reaction is
"enable sandbox", but for blik that costs more than it buys at this phase.

Why sandbox-off was the path of least resistance until now:
- The app does not need filesystem access beyond `~/Library/Logs/Blik/` and the
  standard Keychain. It does need network (OAuth/REST/OTLP) and IPC to the
  privileged helper (Mach service `com.blik.helper`). Both work in a sandboxed
  app with the right entitlements (`com.apple.security.network.client`,
  `com.apple.security.temporary-exception.mach-lookup.global-name`), but the
  exception requires a code-signed app and explicit team-id pairing.
- The project is not signed with an Apple Developer ID at this stage (see
  `decisions/no-apple-dev-id.md`). Without a team-id, an entitled sandboxed
  build cannot connect to the privileged Mach service — sandbox would block
  the only working channel to manage fans.
- All privileged operations live in `BlikHelper` (root, separately running
  daemon). The app process itself does not need elevated privileges; the
  blast radius of compromising the app is limited to:
  - reading `~/Library/Logs/Blik/` log files,
  - sending requests to the helper (now restricted by path-whitelist — see
    `Sources/BlikHelper/ClientAuthorization.swift`),
  - reading tokens from Keychain (ACL is per-bundle-id and locked behind
    `kSecAttrAccessibleAfterFirstUnlock`).

## Decision
Keep app sandbox **disabled** until at least one of these is true:
1. Project receives Apple Developer ID and gets signed → mach-lookup
   entitlement exception becomes possible.
2. Distribution model moves to App Store / TestFlight (sandbox is then
   mandatory anyway).

In the meantime, the privilege boundary is enforced at the *XPC layer* (path
whitelist of allowed client executables) rather than at the OS sandbox layer.

## Consequences

Positive:
- Build & dev flow simple (`swift build && swift run BlikApp` just works).
- No mach-lookup entitlement gymnastics.
- Helper-side authorization (`ClientAuthorization.isAuthorized(pid:)`)
  remains the single chokepoint we maintain — easier to reason about.

Negative:
- A compromised app process has broader access to the user's `$HOME` than a
  sandboxed equivalent would. Mitigations:
  - Sensitive material in Keychain (already done) instead of plain files.
  - Helper rejects connections from non-whitelisted executables, so a
    compromised arbitrary process cannot just call `setFanSpeedPreset` /
    `performUpdate` / `uninstallAll`.

Trackers/reminders to revisit:
- When `decisions/no-apple-dev-id.md` is retired, reopen this one and
  evaluate sandbox-on with entitlements.

## Related
- `Sources/BlikHelper/ClientAuthorization.swift` — path-whitelist
- `decisions/no-apple-dev-id.md` — sister decision
- `Sources/BlikShared/Auth/KeychainStore.swift` — token storage
