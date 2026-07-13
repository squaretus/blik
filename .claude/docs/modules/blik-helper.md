# BlikHelper

## Purpose
Privileged LaunchDaemon executable (root) — the only process system-wide with direct SMC write access. Acts as the XPC service backend for CLI / MenuBar / GUI clients: serialises SMC reads/writes on a single queue, holds forced fan mode alive via a 1 s reinforce timer, caches GitHub Releases checks, and performs self-update / self-uninstall (including bootout of its own launchd job). Gates incoming XPC connections via a path-based client whitelist (`ClientAuthorization`). License validation logic <!-- removed --> has moved out of the helper.

## Key files
- `Sources/BlikHelper/main.swift` — process bootstrap (no `@main`, uses `dispatchMain()`).
- `Sources/BlikHelper/HelperDelegate.swift` — XPC delegate, all protocol implementations, timers, uninstall.
- `Sources/BlikHelper/ClientAuthorization.swift` — path-based whitelist for XPC client PIDs (resolves via `proc_pidpath`).
- `Sources/BlikHelper/UpdateChecker.swift` — GitHub API, PKG download, silent install.
- `Sources/BlikHelper/HelperLogger.swift` — JSON file logger + NSLog mirror, 1 MB rotation.
- `Resources/com.blik.helper.plist` — LaunchDaemon plist (installed to `/Library/LaunchDaemons/`).

## Entry points
- `main.swift` — `HelperDelegate.create()` → `NSXPCListener(machServiceName: BlikXPCConstants.machServiceName)` → `listener.delegate = _delegate` → `listener.resume()` → `dispatchMain()`. Strong globals `_delegate` / `_listener` are mandatory because `NSXPCListener.delegate` is `weak`.
- `HelperDelegate` implements `BlikHelperProtocol` + `NSXPCListenerDelegate`:
  - `listener(_:shouldAcceptNewConnection:)` — resolves client PID via `ClientAuthorization.executablePath`, rejects if not whitelisted (`ClientAuthorization.isAuthorized`); otherwise sets `exportedInterface`/`exportedObject`, wires `invalidationHandler`/`interruptionHandler` to `handleClientDisconnected`, increments `activeConnections`, cancels pending `restoreWorkItem`.
  - Read API: `readAllFans(reply:)`, `readAllSensors(reply:)`, `readState(reply:)` — JSON-encoded SMC reads dispatched onto `smcQueue`. `readResources(reply:)` — returns a raw `ResourceSnapshot` (CPU/RAM/GPU/disk counters via `ResourceReader`), also dispatched onto `smcQueue`; daemon stays stateless (no per-client prev snapshot — delta is the client's job).
  - Write API: `setFanSpeedPreset(percentage:reply:)` — reads fans, calls `writer.setAllFansSpeed`, fills `targetSpeeds` (cleared on 0%); `restoreAutoMode(reply:)` — explicit client-initiated restore.
  - `uninstallAll(reply:)` — restores auto, replies, sleeps 0.5 s, then `performUninstall(removeApp: true)`.
  - `getHelperVersion(reply:)` → `BlikXPCConstants.protocolVersion` (currently `"2.11.0"`) — the XPC-protocol capability level, not the release version; the client's `Constants.minHelperVersionFor*` gates compare against it. See bugs/release-version-vs-protocol-gates.md.
  - License: `validateLicense(key:hardwareId:reply:)` / `getLicenseStatus(reply:)` <!-- removed --> — license logic removed from helper; protocol no longer declares these methods.
  - Update: `checkForUpdate(reply:)` (cache-first), `checkForUpdateForced(reply:)` (always GitHub), `performUpdate(reply:)` (reject if `isUpdating` or no newer version; reply immediately, then download + install on a `userInitiated` queue after 0.5 s).
- `ClientAuthorization` (caseless enum):
  - `executablePath(forPID:)` — `proc_pidpath` lookup, returns absolute path or `nil`.
  - `isAuthorized(pid:)` — `true` only if path matches `installedPaths` (`/Applications/Blik.app/Contents/MacOS/BlikApp|BlikMenuBar`, `/usr/local/bin/blik`); `#if DEBUG` also allows `.build/debug/`, `.build/release/`, Xcode `Build/Products/Debug/` suffixes.
- `UpdateChecker` (caseless enum):
  - `checkLatestRelease(completion:)` — GETs `https://api.github.com/repos/<owner>/<repo>/releases/latest`, 30 s timeout, calls `parseRelease`.
  - `parseRelease(data:)` — `internal`-tested, strips leading `v`, compares to `Constants.appVersion` via `SemanticVersion`.
  - `ensureUpdatesDirectory()` — creates `/var/db/blik/updates` with mode 0700; re-applies 0700 if exists.
  - `downloadPKG(from:completion:)` — downloads via `URLSession.shared.downloadTask`, moves to `/var/db/blik/updates/blik-update.pkg`, chmod 0600.
  - `installPKG(atPath:)` — `Process` → `/usr/sbin/installer -pkg <path> -target /`, blocking; deletes PKG after.
- `HelperLogger.log(_:)` (legacy) and `HelperLogger.log(_:tag:message:data:)` — write `JSONLogFormatter`-formatted line under `NSLock`; mirror a human-readable line via `NSLog`.

## Dependencies
- BlikCore — SMC stack (`SMCConnection`, `SMCReader`, `SMCWriter`), resource stack (`ResourceReader`, `ResourceSnapshot`), models (`FanInfo`, `SensorInfo`, `UpdateInfo`, `SemanticVersion`, `StateSnapshot`), `HardwareID`, `Constants`, `JSONLogFormatter` + `LogLevel`. (Previously also `LicenseChecker` / `LicenseInfo` <!-- removed -->.)
- BlikXPC — `BlikHelperProtocol` (`@objc`), `BlikXPCConstants` (machServiceName `com.blik.helper`, `protocolVersion`).
- Foundation — `NSXPCListener`, `DispatchSource` timers, `URLSession`, `FileManager`, `Process`, `NSLock`, `DispatchWorkItem`.
- Darwin — `proc_pidpath` for resolving XPC client executable paths (`ClientAuthorization`).
- IOKit (transitively via BlikCore) — AppleSMC, `IOPlatformSerialNumber` for hardware ID.
- launchd — `com.blik.helper` registered as a system Mach service in `/Library/LaunchDaemons/com.blik.helper.plist`.
- External network: GitHub Releases API (`api.github.com/repos/squaretus/blik/releases/latest`), GitHub asset download host. (License server endpoint <!-- removed --> from helper.)
- Spawned binaries: `/usr/sbin/installer`, `/bin/launchctl`, `/usr/bin/tccutil`, `/usr/sbin/pkgutil`.

## Side effects
<!-- generated, verify -->
- SMC writes: `Ftst`, `F{n}Md`, `F{n}Tg` for every fan (sequence implemented in `BlikCore/SMC/SMCWriter`). This daemon is the only producer of SMC writes in the system.
- File writes:
  - `/Library/Logs/Blik/helper.log` — one JSON line per call (formatted by `JSONLogFormatter`), rotated to `helper.log.old` when size exceeds 1 MB. Directory + file created lazily on first log.
  - `/var/db/blik/updates/blik-update.pkg` — root-only directory (0700) created by `ensureUpdatesDirectory`; PKG written with mode 0600. Removed by `installPKG` after `installer` returns. (Previously `/tmp/blik-update.pkg` <!-- removed -->.)
  - `/Library/Application Support/blik/license.key` <!-- removed --> — helper no longer writes a license key; the legacy directory is only deleted as part of `performUninstall`.
- File deletions during `performUninstall(removeApp:)`:
  - `/usr/local/bin/blik`
  - `/Library/LaunchAgents/com.blik.app.plist`
  - `/Applications/Blik.app` (only when `removeApp == true`)
  - `/Library/LaunchDaemons/com.blik.helper.plist`
  - `/Library/PrivilegedHelperTools/com.blik.helper`
  - `/Library/Application Support/blik/` (legacy cleanup — only if directory exists; key-based license no longer used)
  - For every `/Users/*` entry: `~/Library/Logs/Blik`, `~/Library/Logs/blik`, `~/Library/Preferences/com.blik.*`, `~/Library/Caches/com.blik.*`.
- Process invocations during uninstall: `launchctl bootout gui/<uid>/com.blik.app` for every real user (uid derived from `attributesOfItem(atPath: /Users/<user>)[.ownerAccountID]`), `tccutil reset All com.blik.app`, `pkgutil --forget com.blik.pkg`, `launchctl bootout system/com.blik.helper` (terminates self).
- Network: HTTPS GET to GitHub Releases API (30 s timeout, no backoff), HTTPS GET to download PKG. (HTTPS POST to license server <!-- removed -->.)
- NSLog → syslog (visible via `log stream --predicate 'process == "BlikHelper"' --info`).
- DispatchSourceTimers (background threads): reinforce 1 s on `smcQueue` (kicks off after 1 s deadline); update check 6 h on global utility QoS (initial delay 10 s via `Constants.updateCheckInitialDelay`). License check timer <!-- removed -->.
- Spawns `/usr/sbin/installer` with root context — the PKG's `preinstall` script bootouts the current daemon, so the current process is killed mid-call. Anything after `installPKG` in the success path is unreachable.

## Invariants / assumptions
<!-- generated, verify -->
- Runs as root via launchd LaunchDaemon. Cannot run as a normal user — SMC writes require root and writes to `/Library/...` are root-only.
- Single instance system-wide: launchd guarantees one process per Mach service name `com.blik.helper`.
- All SMC operations go through the serial `smcQueue` (`com.blik.helper.smc`) — XPC reply handlers, reinforce timer event handler, and `uninstallAll` cleanup all dispatch onto it. SMC stack is treated as not thread-safe.
- XPC connections are gated by `ClientAuthorization.isAuthorized(pid:)` — only PIDs whose executable path matches the installed-binary whitelist (plus `#if DEBUG` paths) are accepted. Threat model: path-based check stops user-mode impostors; does not defend against a root attacker who can overwrite the whitelisted binaries.
- `targetSpeeds`, `cachedUpdate`, `isUpdating`, `appExistedOnStart` are not locked and assumed to be mutated from a single logical context each. (`licenseKey` / `cachedLicenseInfo` <!-- removed -->.)
- `activeConnections` is shared across the XPC accept queue and the 5 s delayed restore block — guarded by `connectionLock`.
- `restoreWorkItem` is touched from the XPC accept queue and the delayed block itself — assumed effectively serialised by short critical sections, not explicitly locked.
- On startup the helper does NOT proactively reset fans — it inherits whatever SMC state exists. Auto restore happens only on explicit client call, on the 5 s-after-last-disconnect window, on `uninstallAll`, or on Finder-removal self-cleanup.
- `cachedUpdate` is populated lazily: `checkForUpdate` falls through to GitHub on cache miss; `checkForUpdateForced` always hits GitHub.
- `performUpdate` is single-flight under concurrent calls — `isUpdating` flag rejects duplicates with `"Обновление уже выполняется"`.
- `appExistedOnStart` enables the "app removed from Finder" self-uninstall path. If the daemon started before `/Applications/Blik.app` existed (rare dev scenario), self-uninstall via Finder removal is disabled for the lifetime of the process.
- Update PKG lives in `/var/db/blik/updates/` with permissions 0700 on the directory and 0600 on the file — root-only access closes the TOCTOU window between download and `installer -pkg` invocation.
- Version strings drop a leading `v` from GitHub tags (`v1.2.0` → `1.2.0`) before `SemanticVersion` parsing; non-semver tags fail with `UpdateError.invalidVersion`.

## Failure hotspots
<!-- generated, verify -->
- **Reinforce timer contention**: every 1 s on `smcQueue` the timer reads `writer.modifiedFanIds`, replays `F{n}Tg`, and performs the Finder-existence self-uninstall check. A long `readState` or `setFanSpeedPreset` ahead of it on the same queue delays reinforce and fans may briefly drift. Symptom: RPM oscillation under load.
- **5 s auto-restore window**: short reconnects (MenuBar relaunch, CLI restart) are tolerated, but a >5 s client gap silently restores auto and kills the user-set preset. Symptom: fans revert to auto after MenuBar quit + delayed reopen.
- **Self-uninstall trigger by `/Applications/Blik.app` existence**: re-evaluated every 1 s in `reinforceAllFans` (when no clients are connected). A transient unmount or permission glitch could trigger a real uninstall. Only mitigation is the `appExistedOnStart` gate; no debounce.
- **`installPKG` is fire-and-forget by design**: invoked from a global `userInitiated` queue 0.5 s after `performUpdate` reply. The PKG's `preinstall` runs `launchctl bootout system/com.blik.helper`, so the daemon is killed mid-call; any state mutation after `installPKG` (e.g. `isUpdating = false`) is unreachable in the happy path.
- **`uninstallAll` reply ordering**: reply is sent first, then 0.5 s sleep, then deletions. If the client tears down the XPC connection in <0.5 s the reply may be lost; once `bootout system/com.blik.helper` runs near the end, the daemon disappears mid-cleanup if any earlier step hung.
- **`ClientAuthorization` is path-based, not signature-based**: a root attacker who replaces a whitelisted binary at `/Applications/Blik.app/...` or `/usr/local/bin/blik` is silently accepted. Production builds should migrate to `SecCodeCheckValidity` with a Developer-ID requirement once the app is signed.
- **GitHub rate limiting / network errors**: `checkLatestRelease` has no backoff. The 6 h timer plus `checkForUpdateForced` from multiple clients can hit `403 rate limit exceeded`. Cached value is preserved on failure, but `checkForUpdate` returns an error on cache miss + network failure.
- **Log rotation race**: `rotateIfNeeded` closes the file handle, moves the file, recreates it, reopens — all inside `lock`. Sustained logging with rotation is bounded by lock contention but adds a stall on every rotation boundary.
- **`HelperLogger.log` is not async-signal-safe**: do not call from signal handlers.
- **`HelperDelegate.create()` failure at startup**: `main.swift` logs and exits with code 1; launchd will restart per plist `KeepAlive` policy — crash loop if SMC is unavailable on the host.

## Related docs
- modules/blik-core.md (SMC stack, models, `JSONLogFormatter`)
- modules/blik-xpc.md (`BlikHelperProtocol`, `BlikXPCClient`, machServiceName)
- runbooks/helper-logs.md (where to look when the daemon misbehaves)
- features/auto-update.md
- features/uninstall-flow.md
- decisions/daemon-centric-update.md
