# BlikXPC

## Purpose
Cross-process contract between the privileged `BlikHelper` daemon (root) and unprivileged clients (`blik` CLI, `BlikMenuBar`, `BlikApp`). Owns the single `@objc` XPC protocol, the Mach service name and XPC-protocol version constant, a connection wrapper that exposes both raw `@objc` proxy access and `DispatchSemaphore`-based sync wrappers for the CLI, plus the `UpdateService` facade that hides the proxy/JSON dance behind a result-typed API (sync flavor for CLI, async flavor for SwiftUI).

The module is pure plumbing: no SMC, no filesystem, no networking — all of those live behind the XPC boundary in `BlikHelper`. Its only data dependency is on the `Codable` payload types from `BlikCore`.

## Key files
- `Sources/BlikXPC/BlikHelperProtocol.swift`
- `Sources/BlikXPC/XPCConstants.swift`
- `Sources/BlikXPC/BlikXPCClient.swift`
- `Sources/BlikXPC/UpdateService.swift`

## Entry points

### Constants
- `BlikXPCConstants.machServiceName: String` — `"com.blik.helper"`. Must match `NSXPCListener(machServiceName:)` in `Sources/BlikHelper/main.swift` and `MachServices` in `Resources/LaunchDaemon.plist`.
- `BlikXPCConstants.protocolVersion: String` — XPC-protocol capability level (currently `"2.11.0"`). **Decoupled from the marketing release version (`Constants.appVersion`) — `scripts/build.sh` does NOT substitute it.** Bumped manually only when the XPC surface changes (new methods / payload contracts). The client's `Constants.minHelperVersionFor*` capability gates compare against this value; a gate must never exceed the current `protocolVersion` (invariant locked by `Tests/BlikXPCTests/XPCProtocolVersionTests.swift`). Formerly named `helperVersion` and stamped with the release version — that caused the release-version-vs-protocol-gates regression (see bugs/release-version-vs-protocol-gates.md).

### `BlikHelperProtocol` (`@objc public`)
The complete XPC ABI. All methods take `@escaping` reply blocks; reply payloads use the conventions "`Data?` = JSON-encoded `Codable` (nil on error)" and "`String?` = nil on success, non-nil error message".

- `readAllFans(reply: (Data?, String?) → Void)` — `[FanInfo]` JSON.
- `readAllSensors(reply: (Data?, String?) → Void)` — `[SensorInfo]` JSON.
- `readState(reply: (Data?, String?) → Void)` — `StateSnapshot` JSON (`{fans, sensors}` combined; single round-trip instead of two). Consumed by `FanControlVM` in `BlikShared`; no sync wrapper exists on the client.
- `readResources(reply: (Data?, String?) → Void)` — `ResourceSnapshot` JSON (raw point-in-time counters). The daemon is **stateless** here — it returns raw counters only; the client (`ResourceVM`) holds the previous snapshot and runs `ResourceUsageCalculator` to derive `%`/rate. Has a sync wrapper (`readResourcesSync`).
- `setFanSpeedPreset(percentage: Int, reply: (String?) → Void)` — `0` = auto, `25/50/75/100` = manual percentage; applies to all fans atomically.
- `restoreAutoMode(reply: (String?) → Void)` — equivalent to `setFanSpeedPreset(percentage: 0)`.
- `getHelperVersion(reply: (String) → Void)` — replies `BlikXPCConstants.protocolVersion`; used as a ping by `connectAndVerify()` and as the source of the daemon's protocol level for the client capability gates. Non-optional `String` return distinguishes it from data calls.
- `uninstallAll(reply: (String?) → Void)` — daemon-side full uninstall (binaries, plists, logs, TCC, PKG receipt).
- `checkForUpdate(reply: (Data?, String?) → Void)` — `UpdateInfo` JSON from daemon cache.
- `checkForUpdateForced(reply: (Data?, String?) → Void)` — `UpdateInfo` JSON from a fresh GitHub Releases API call.
- `performUpdate(reply: (String?) → Void)` — daemon downloads PKG and runs `installer -pkg`.
<!-- removed: validateLicense(key:hardwareId:reply:) — license endpoints no longer in BlikHelperProtocol -->
<!-- removed: getLicenseStatus(reply:) — license endpoints no longer in BlikHelperProtocol -->

### `BlikXPCClient` (public class)
Connection wrapper. One instance per process, owned by `BlikShared.BlikRuntime` for SwiftUI clients or constructed directly in `XPCFanController` for the CLI.

- `init()` — no side effects.
- `connect()` — opens `NSXPCConnection(machServiceName:options: .privileged)`, sets `remoteObjectInterface`, installs `invalidationHandler` / `interruptionHandler` (both nil out the stored connection under `NSLock`), then `resume()`.
- `connectAndVerify() → Bool` — calls `connect()` then pings via `getHelperVersion` with a 2 s `DispatchSemaphore` timeout. On timeout/failure: `disconnect()` and returns `false`.
- `disconnect()` — `connection?.invalidate()`, stores `nil`.
- `isConnected: Bool` — non-nil check under lock.
- `helper() → BlikHelperProtocol?` — public alias for the private `proxy()`. Returns `remoteObjectProxyWithErrorHandler` cast; logs proxy errors via `NSLog("BlikXPCClient: remote object proxy error: ...")`.

### `BlikXPCClient` sync wrappers (CLI path)
All wrappers use `DispatchSemaphore` to block the caller until the XPC reply or per-call timeout. Implemented via two private generics: `callSync<T: Decodable>` (for `Data?`/`String?` replies, JSON-decodes to `T`) and `callErrorSync` (for `String?`-only replies).

| Wrapper | Returns | Timeout | Backing protocol method |
|---|---|---|---|
| `readAllFansSync()` | `[FanInfo]?` | `.distantFuture` | `readAllFans` |
| `readAllSensorsSync()` | `[SensorInfo]?` | `.distantFuture` | `readAllSensors` |
| `readResourcesSync()` | `ResourceSnapshot?` | `.distantFuture` | `readResources` |
| `setFanSpeedPresetSync(percentage:)` | `String?` | `.distantFuture` | `setFanSpeedPreset` |
| `restoreAutoModeSync()` | `String?` | `.distantFuture` | `restoreAutoMode` |
| `checkForUpdateSync()` | `UpdateInfo?` | 5 s | `checkForUpdate` |
| `checkForUpdateForcedSync()` | `UpdateInfo?` | 10 s | `checkForUpdateForced` |
| `performUpdateSync()` | `String?` | `.distantFuture` | `performUpdate` |
| `uninstallAllSync()` | `String?` | `.distantFuture` | `uninstallAll` |
<!-- removed: validateLicenseSync / getLicenseStatusSync — license endpoints no longer in protocol -->

### `UpdateService` (caseless enum)
Facade that hides JSON decoding, `nil` handling, and the proxy lookup from update callers.

- `UpdateService.CheckResult` — `.available(UpdateInfo)` / `.upToDate(currentVersion: String)` / `.error(String)`.
- `UpdateService.InstallResult` — `.started` / `.error(String)`.
- Sync API (CLI):
  - `check(client:) → CheckResult` — cached daemon read.
  - `checkForced(client:) → CheckResult` — fresh GitHub read.
  - `checkAndInstall(client:) → CheckResult` — forces a check, then triggers `performUpdateSync`; on install failure returns `.error("Ошибка обновления: …")`, on success returns `.available(info)`.
- Async API (MenuBar / App):
  - `check(helper:completion:)` — direct proxy call, then `handleUpdateReply`.
  - `checkForced(helper:completion:)`.
  - `install(helper:completion:) → InstallResult`.

Sync API discards the daemon-supplied error string when `info == nil` and substitutes `"Не удалось проверить обновления"`. Async API preserves the original `error` string from the protocol reply.

## Dependencies
- `BlikCore` — `FanInfo`, `SensorInfo`, `StateSnapshot`, `ResourceSnapshot`, `UpdateInfo` (all `Codable`), `SemanticVersion`, plus `Constants.minHelperVersionFor*` gates that are compared against `protocolVersion`. <!-- LicenseInfo removed: license endpoints no longer in BlikXPC -->
- `Foundation` — `NSXPCConnection`, `NSXPCInterface`, `DispatchSemaphore`, `JSONDecoder`, `NSLock`, `NSLog`.
- No third-party packages.
- Runtime: Mach service `com.blik.helper` must be published by `BlikHelper` via `launchd` (`/Library/LaunchDaemons/com.blik.helper.plist`). Without a registered listener, `connect()` still appears to succeed locally but no replies arrive.

## Side effects
<!-- generated, verify -->
- Opens a privileged `NSXPCConnection` with the `.privileged` option. Lives until `disconnect()` or invalidation/interruption (daemon crash, reinstall, bootout).
- Sync wrappers park the calling thread on a `DispatchSemaphore` until the reply lands or the per-call timeout elapses. Calls with `.distantFuture` timeout can hang indefinitely if the daemon is wedged or unresponsive.
- All `Data?` payloads are JSON-encoded `Codable` types. Decoding uses `try?` and silently returns `nil` on failure — no error path distinguishes "transport failure" from "schema mismatch".
- Connection-side errors print to `NSLog` as `"BlikXPCClient: remote object proxy error: \(error)"`. No structured logging.
- Reply blocks from XPC fire on a private XPC queue, not on the calling thread or main actor. SwiftUI callers that consume `helper()` directly must hop back to `@MainActor` before mutating `@Observable` state (see `BlikShared.FanControlVM`).
- No filesystem, network, SMC, or `launchctl` interaction inside this module — those side effects all live behind the protocol in `BlikHelper`.

## Invariants / assumptions
<!-- generated, verify -->
- `BlikXPCConstants.machServiceName` is the single source of truth for the Mach name. It must remain equal to the `MachServices` key in `Resources/LaunchDaemon.plist` and the argument to `NSXPCListener(machServiceName:)` in `BlikHelper/main.swift`. Divergence makes the connection silently dead.
- `BlikHelperProtocol` is the **only** ABI between client and daemon. Adding, removing, reordering, or changing method signatures is a breaking change across processes; client and daemon binaries must be rebuilt and re-installed in lockstep. `getHelperVersion` and `BlikXPCConstants.protocolVersion` exist precisely so a client can detect protocol drift after PKG upgrades — `protocolVersion` tracks XPC-surface capability, NOT the marketing release, and is bumped manually (build.sh must not stamp it, or the client's own capability gates break — `XPCProtocolVersionTests`).
- `Data?` payloads carry JSON of the statically-expected `Codable` type. There is no version tag, discriminator, or fallback shape — schemas are coupled by type identity in `BlikCore`.
- `String?` reply parameters follow "nil = success, non-nil = error message". All `…Sync` wrappers that return `String?` preserve this convention.
- `BlikXPCClient` is intended as a long-lived singleton per process (held by `BlikRuntime` for SwiftUI clients, by `XPCFanController` for CLI). Reconnect after invalidation is the caller's responsibility — the client only nils its `connection` field and does not auto-reconnect.
- All public mutation of `connection` is guarded by `NSLock`. `proxy()` snapshots the connection under the lock before calling `remoteObjectProxyWithErrorHandler`. The semaphore-based sync wrappers are safe to call from any thread.
- `UpdateService.evaluate(_:)` flattens any failure into the same generic message `"Не удалось проверить обновления"`. Callers needing the underlying error must use the async API and read the protocol-level `error` string directly.
<!-- removed: license reply-block shape invariant — license endpoints no longer in protocol -->

## Failure hotspots
<!-- generated, verify -->
- **Daemon not running / not registered.** `connect()` returns silently and `proxy()` produces a usable proxy object, but replies never arrive. Wrappers with `.distantFuture` timeout (`readAllFansSync`, `readAllSensorsSync`, `setFanSpeedPresetSync`, `restoreAutoModeSync`, `uninstallAllSync`, `performUpdateSync`) block the caller indefinitely. Always run `connectAndVerify()` (2 s timeout via `getHelperVersion`) before issuing real calls and treat its `false` return as "fall back to direct SMC or surface unavailable state".
- **Schema drift after upgrade.** If a `Codable` payload type in `BlikCore` changes shape on one side only, `try? JSONDecoder().decode(...)` returns `nil` and the wrapper surfaces "no data". The daemon's error string is **not** populated in this case because decoding fails on the client. Bump `protocolVersion` and verify both sides on any protocol-adjacent change.
- **Release version stamped into `protocolVersion`.** Historically `build.sh` `sed`ed the marketing version into this constant; a release number below a `minHelperVersionFor*` gate made a freshly built helper fail its own capability checks → «история недоступна» + legacy double-round-trip live polling. `protocolVersion` must stay decoupled from the release; `XPCProtocolVersionTests` guards it. See bugs/release-version-vs-protocol-gates.md.
- **Reply block invoked twice or never.** XPC crashes the *daemon* process if a reply block is called more than once, and the *client* sync wrapper hangs until timeout if a reply path forgets to call back. Server-side discipline lives in `BlikHelper.HelperDelegate`; any new method must trace every code path to exactly one reply.
- **`callErrorSync` connection-loss path.** When `proxy()` returns `nil` (e.g. invalidated connection), the wrapper synthesizes `"XPC connection not established"`. When the reply never fires, the pre-seeded `"XPC call did not complete"` survives; on timeout the wrapper substitutes `"XPC call timed out"`. Callers must distinguish these synthetic errors from a real daemon-reported error string — all are surfaced as `String?` non-nil with no discriminator.
- **`.privileged` option requires a privileged listener.** The Mach service must be installed as a LaunchDaemon (root), not a LaunchAgent. Running a SwiftUI client against a dev `swift build` without the PKG-installed daemon will fail to bind, and the failure surfaces only as "replies never arrive" — see the first hotspot.
- **`UpdateService.checkAndInstall` for CLI (`blik --update`).** Bundles two blocking XPC calls back-to-back, with `performUpdateSync` using `.distantFuture`. If the daemon stalls during PKG download, the CLI hangs with no UI feedback. Run off the main thread when invoked from a TUI context.
- **`@AppStorage`-style callbacks on the XPC queue.** Replies arrive on an XPC private queue. SwiftUI clients that bypass the sync wrappers and consume `helper()` directly **must** wrap state mutations in `Task { @MainActor in ... }`; this is project convention and is enforced in `BlikShared` VMs but not by this module.
- **`readState` has no sync wrapper.** Only async consumers (`FanControlVM` polling Task) use it. Anyone adding a CLI consumer must either add `readStateSync` or accept the double round-trip via `readAllFansSync` + `readAllSensorsSync`.

## Related docs
- modules/blik-helper.md
- modules/blik-core.md
- modules/blik-shared.md
- modules/blik-cli.md
- modules/blik-menubar.md
- modules/blik-app.md
- bugs/release-version-vs-protocol-gates.md
