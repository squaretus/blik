# System Overview

Five long-lived processes share state through one privileged daemon plus an external licensing server:

- `BlikHelper` — root LaunchDaemon, **only** process with direct SMC write access. Owns SMC connection, fan reinforce timer, update cache, license cache.
- `BlikApp` — GUI (`Window` + native `Settings` scene + `MenuBarExtra`). Owns the OAuth/PAT auth stack and device management. Uses `AppCoordinator` from `BlikShared`.
- `BlikMenuBar` — second `MenuBarExtra` executable (separate process). Same `AppCoordinator`, no `Settings` scene; defers settings to `BlikApp` via `blik://` deep link.
- `blik` — CLI, can run direct-SMC (sudo) or through XPC. **Has its own independent PAT auth stack** (`AuthStorage` + `CLIAPIClient`), bypassing `BlikShared`'s OAuth.
- Clients reach the daemon via `NSXPCConnection(machServiceName: BlikXPCConstants.machServiceName, options: .privileged)` → `BlikHelperProtocol` (`@objc`).

Fan/license/update state goes through XPC. Auth (OAuth tokens, PAT, profile, devices) goes through HTTPS to `Constants.licenseServerURL` and is **never** routed through `BlikHelper`. Shared filesystem state: `/Library/Application Support/blik/license.key` (daemon, lowercase `blik`) and `~/.config/blik/auth.json` (CLI PAT only).

## Data Flows

### 1. Fan control through XPC (M4 unlock sequence)

```
BlikApp/BlikMenuBar (SwiftUI button)
  └─ FanControlVM.setSpeedPreset(percentage:)            [MainActor]
      ├─ optimistic UI: fans[i].isForced = true, isUnlocking = true
      └─ runtime.xpcClient.helper().setFanSpeedPreset(percentage:, reply:)
                                                          ▼
                                                NSXPCConnection (Mach service "com.blik.helper")
                                                          ▼
BlikHelper.HelperDelegate.setFanSpeedPreset(percentage:)  [smcQueue: serial DispatchQueue]
  ├─ reader.readAllFans()                                 (latest fan list — for isForced check)
  ├─ writer.setAllFansSpeed(percentage: fans:)
  │     ├─ ensureUnlocked():
  │     │     ├─ writeKey("Ftst", ui8, 1)               // thermalmonitord unlock
  │     │     └─ Thread.sleep(5.0)                       // HARDCODED literal in SMCWriter,
  │     │                                                //   NOT Constants.ftstUnlockDelay (3.0 — dead code)
  │     └─ per fan:
  │           ├─ if !isForced → setForcedMode(enabled: true)
  │           │     └─ writeKey("F{n}Md", ui8, 1) with up-to-5 retries (2s gap each)
  │           └─ setFanSpeed(rpm:) → writeKey("F{n}Tg", flt/fpe2)
  ├─ targetSpeeds[fan.id] = rpm                           // remembered for reinforce
  └─ reply(nil)
                                                          ▼
HelperDelegate.reinforceTimer (DispatchSourceTimer, 1 s, on smcQueue)
  └─ for each modifiedFanId: writer.reinforceSpeed(fan:, rpm: targetSpeeds[fanId])
                                                          ▲
                                                          │ runs forever while clients are connected
                                                          │
Restore path:
  - percentage == 0 → writer.restoreAutoMode() → F{n}Md=0 for all fans, Ftst=0
  - client invalidation → handleClientDisconnected() → after 5 s with 0 active connections → restoreAutoMode()
  - NSApplication.willTerminate (BlikApp/BlikMenuBar) → AppCoordinator → runtime.cleanup()
```

XPC callbacks land on the XPC queue. `FanControlVM` wraps every mutation of `@Observable` state in `Task { @MainActor in ... }` (this is the single biggest correctness rule across the VM layer).

Direct-SMC path (sudo CLI, sudo MenuBar) skips XPC entirely: `BlikRuntime.writer` is a local `SMCWriter` and the unlock sequence runs in-process.

### 2. Auto-update (daemon-centric)

```
BlikHelper boot
  └─ updateTimer (DispatchSourceTimer, +10 s, then every 6 h)
        └─ UpdateChecker.checkLatestRelease()
              ├─ GET https://api.github.com/repos/{owner}/{repo}/releases/latest
              ├─ parseRelease(data:)  → SemanticVersion(current) < SemanticVersion(latest) → isNewer
              └─ HelperDelegate.cachedUpdate = info       (in-memory only)

Client poll (BlikApp/BlikMenuBar/CLI):
  UpdateVM.init / 6h Task / manual button
    └─ UpdateService.checkForced(helper:)
          └─ helper.checkForUpdateForced  →  always re-hits GitHub, refreshes cache
  (legacy: helper.checkForUpdate         →  cached value, fresh fetch if cache empty)
                                                          ▼
                                                UpdateInfo (Codable JSON)
                                                          ▼
                                                UpdateVM.availableUpdate (@Observable)
                                                          ▼
                                          banner in OverviewPage / UpdatesPage / MenuBar popup

User clicks "Обновить":
  UpdateVM.installUpdate()
    ├─ helper.performUpdate(reply:)
    │   (daemon replies nil immediately, then on background queue:)
    │     └─ UpdateChecker.downloadPKG(from:)              → /tmp/blik-update.pkg
    │           └─ UpdateChecker.installPKG(atPath:)
    │                 └─ /usr/sbin/installer -pkg ... -target /   (silent)
    │                       ├─ preinstall  → launchctl bootout system/com.blik.helper
    │                       │                (daemon dies here — XPC connection drops)
    │                       └─ postinstall → launchctl bootstrap (new daemon binary)
    └─ installMonitorTask (poll every 3 s):
          when xpcClient.isConnected becomes false → shouldTerminate = true
          → AppCoordinator replicates into fan.shouldTerminate
          → MainContentView.onChange → NSApp.terminate
          → LaunchAgent relaunches BlikApp
```

`UpdateInfo` lives in `BlikCore` (Codable). `SemanticVersion` from `BlikCore` is `Comparable`. `Constants.appVersion` is patched by `scripts/build.sh` before compile.

### 3. License flow

```
BlikCore.HardwareID.get()           → IOPlatformSerialNumber (IOKit)
Key storage                          → /Library/Application Support/blik/license.key (lowercase, daemon-only)
Server                               → Constants.licenseServerURL (HTTP POST)
```

Activation (one-time, user enters key) — legacy path still used by `--license <KEY>` and the BlikApp Account/Devices flows that pre-date OAuth:

```
PreferencesView / LicenseCard (BlikApp) — legacy CTA path
  └─ LicenseVM.saveLicenseKey(key)
        └─ helper.validateLicense(key:, hardwareId:, reply:)
              └─ HelperDelegate (background queue):
                    ├─ saveLicenseKey(key) → writes to /Library/Application Support/blik/license.key
                    ├─ LicenseChecker.validate(key:, hardwareId:, serverURL:)   (HTTP POST, sync via semaphore)
                    └─ cachedLicenseInfo = info
                          (network error → returns cached info if present, else nil)
        └─ reply(Data?)
              └─ LicenseVM.licenseStatus / licenseInfo / licenseActivationResult (5 s auto-clear)
```

Periodic check (daemon, every 6 h):

```
HelperDelegate.licenseTimer
  └─ performLicenseCheck()
        └─ LicenseChecker.validate(...)   → cachedLicenseInfo updated (only on success)
```

Client read (cold-retry: `LicenseVM.checkTask` polls every 2 s for up to 30 s while daemon cache warms, then 6 h):

```
LicenseVM
  └─ helper.getLicenseStatus(reply:)        → returns cachedLicenseInfo or nil
        → LicenseStatus drives UI gates

CLI (`blik` without flags, XPC-TUI branch only):
  Blik.enforceLicense(client:)
    └─ client.getLicenseStatusSync()
          - nil          → stderr hint, exit code 2
          - != .valid    → stderr reason + hint, exit code 2
          - .valid       → continue into TUI
  Skipped paths: --license, --token, --logout, --update, --diagnose, --once, --read-only
  CRITICAL GAP: sudo blik (direct-SMC) bypasses the license check entirely.
```

UI gating on invalid license (in `BlikApp` and `BlikMenuBar`):

- Overview and Sensors/Temperature tab bodies are replaced by `BlikLicenseGate` (CTA → opens native `Settings` scene). Preferences scene is always reachable.
- MenuBar icon: `MenuBarImageRenderer.image(nil, nil, nil)` → "— RPM  —°C".
- MenuBar popup: fans/presets are replaced by `BlikLicenseGate` whose CTA calls `openSettings()` → `blik://settings`.

### 4. Cross-process navigation BlikMenuBar → BlikApp (deep links)

```
BlikMenuBar.FanDetailView.openSettings()
  └─ NSWorkspace.shared.open(URL(string: "blik://settings")!)
        │
        ▼  (system routes URL to BlikApp because BlikApp declares the scheme)
        │
BlikApp process — TWO entry points to handle cold vs warm start:
  ├─ Warm (SwiftUI scene already alive):
  │     Window.onOpenURL { url in coordinator.handleDeepLink(url) }
  │
  └─ Cold (process spawned by URL, SwiftUI scene not ready):
        AppDelegate.application(_:open:)
          └─ pendingDeepLinkURLs.append(url)
        MainContentView.onAppear
          └─ delegate.consumePendingDeepLink(into: coordinator)
                └─ for each saved URL: coordinator.handleDeepLink(url)

AppCoordinator.handleDeepLink(url)
  ├─ blik://auth?code=...&state=...     → auth.handleCallback(url)   (Task on MainActor)
  ├─ blik://overview                    → pendingTab = .overview
  ├─ blik://temperature                 → pendingTab = .temperature
  ├─ blik://settings                    → fallback → pendingTab = .overview      (* see hotspot)
  └─ unknown host/path                  → fallback → pendingTab = .overview      (logged)

MainContentView.onChange(of: coordinator.pendingTab)
  └─ selectedTab = tab
  └─ coordinator.pendingTab = nil          (consumed)
```

`SidebarTab` is exposed in `BlikShared` with only **two** cases — `.overview` and `.temperature`. Settings is a separate `Settings` scene in `BlikAppMain`, **not** a sidebar tab, so `blik://settings` cannot land via `pendingTab` — the deep-link is silently coerced to `.overview` (failure hotspot: clicking "Настройки" in BlikMenuBar opens BlikApp on Overview rather than Settings unless the receiving side also pops the native Settings window).

`Window` does **not** support `.handlesExternalEvents` — only `.onOpenURL` works. AppDelegate is mandatory as the cold-start backstop.

### 5. Sleep/wake handling

```
NSWorkspace.shared.notificationCenter (system-level)
  ├─ NSWorkspace.willSleepNotification ───┐
  └─ NSWorkspace.didWakeNotification  ────┤
                                          ▼
FanControlVM.startSleepWakeObservers() (addObserver — Notification is NOT Sendable under Swift 6,
                                       so async sequences won't compile; stored token + closure
                                       hopping to MainActor is the only viable form)
  ├─ willSleep → pauseForSleep():
  │     isSleeping = true
  │     pollingTask?.cancel(); pollingTask = nil
  └─ didWake   → resumeAfterWake():
        isSleeping = false
        restartPolling()  → spawn new Task running pollLoop() (reads settings.pollIntervalSeconds live)
```

Observer tokens are stored on the VM and removed in `deinit` (`NSWorkspace.shared.notificationCenter.removeObserver(token)`). The polling Task itself is cancelled by `deinit` without `await` because `Task.cancel()` is nonisolated.

The same VM also reacts to `settings.pollIntervalSeconds` changes via `AppCoordinator.observePollInterval()` (rolling `withObservationTracking`), which calls `fan.restartPolling()` — so wake-up and interval-change funnel through the same restart entry point.

### 6. Authentication (OAuth PKCE — BlikShared GUI stack)

<!-- generated, verify -->

Used by `BlikApp` and `BlikMenuBar`. Independent from CLI's PAT stack and from the daemon's license-key path.

```
PreferencesView/AccountPage or SidebarUserWidget "Войти"
  └─ AuthVM.startLogin()                                  [MainActor]
        └─ OAuthClient.startLoginFlow()
              ├─ SecRandomCopyBytes(64) → verifier
              ├─ UserDefaults["_oauth_pkce_verifier"] = verifier  (cleartext — survives app death)
              ├─ SHA256(verifier) → base64URL → code_challenge
              └─ NSWorkspace.shared.open(authorize URL)
                    └─ opens system browser at
                       Constants.licenseServerURL + "/oauth/authorize?..."

User authenticates in browser → server redirects to blik://auth?code=...&state=...
                                                          ▼
BlikApp receives URL (warm: .onOpenURL; cold: AppDelegate.application(_:open:))
  └─ AppCoordinator.handleDeepLink(url)                   [host == "auth"]
        └─ Task { await auth.handleCallback(url) }
              └─ OAuthClient.handleCallback(url)
                    ├─ reads UserDefaults["_oauth_pkce_verifier"], then clears it
                    ├─ POST {licenseServerURL}/api/v1/oauth/token
                    │      (grant_type=authorization_code + code + code_verifier)
                    └─ returns TokenResponse(access_token, refresh_token, expires_in)
              └─ KeychainStore.save(.accessToken / .refreshToken / .expiresAt)
                    (service "com.blik.auth", kSecAttrAccessibleAfterFirstUnlock)
              └─ APIClient.get("/api/v1/users/me") → UserProfile
              └─ AuthVM.state = .authenticated(profile)

AppCoordinator.observeAuthChanges()
  └─ on .authenticated → devices.registerCurrent()
  └─ on .loggedOut    → clear devices/subscription/seatLimit
```

API call with auto-refresh (single-flight):

```
APIClient.request(path, method, ...)
  ├─ access_token from Keychain
  ├─ if expires_at < now → preflight refresh
  ├─ HTTP call with Bearer header
  ├─ if 401 → RefreshCoordinator.ensureFreshToken()       (actor: at most one refresh in flight,
  │            └─ OAuthClient.refresh(refreshToken)         concurrent 401s await same Task)
  │                  → KeychainStore.save(new tokens)
  │            └─ retry once with new access_token
  └─ decode JSON to T
```

Logout:

```
AuthVM.logout()
  ├─ OAuthClient.revoke(refreshToken) (best-effort, ignores network failure)
  ├─ KeychainStore.deleteAll()           (com.blik.auth service)
  ├─ AuthVM.state = .loggedOut
  └─ AppCoordinator.observeAuthChanges() → DeviceVM cleared
```

CLI's authentication is **separate**: `--token <PAT>` writes a personal access token to `~/.config/blik/auth.json` (chmod 600). `BLIK_API_TOKEN` env always wins. `BLIK_API_URL` env overrides `Constants.licenseServerURL`. `CLIAPIClient` is sync (semaphore + 15 s timeout), no auto-refresh, no Keychain — PATs are long-lived. Used only on `--token` and `--logout`; TUI itself does not call HTTP.

### 7. Devices and seats

<!-- generated, verify -->

```
AppCoordinator.init
  └─ Task: await auth.bootstrap()
        └─ if authenticated → devices.registerCurrent()

DeviceVM.registerCurrent()                                [MainActor]
  ├─ APIClient.post("/api/v1/me/devices", body: {hardware_id, name, model})
  │     ├─ hardware_id from BlikCore.HardwareID.get()
  │     ├─ name from Host.current().localizedName ?? "Mac"
  │     └─ on HTTP 402 (seat limit exceeded):
  │           ├─ refresh()                  → loads /api/v1/me/devices + /me/subscription
  │           └─ seatLimit = SeatLimitError(seats, used, devices)
  ├─ on success → currentDeviceId = response.id, devices refresh
  └─ idempotent by hardware_id (server-side dedup)

DeviceVM.refresh()
  ├─ APIClient.get("/api/v1/me/devices")        → [Device]
  └─ APIClient.get("/api/v1/me/subscription")   → Subscription (seats_total, seats_used, plan)

DeviceVM.rename(deviceId, to: newName)
  └─ APIClient.patch("/api/v1/me/devices/{id}", body: {name: newName})
        → on success: refresh()

DeviceVM.remove(deviceId)
  └─ APIClient.deleteReturning("/api/v1/me/devices/{id}")
        → on success: refresh()
        → if removed device == currentDeviceId → registerCurrent() retry
```

`DevicesPage` in `BlikApp.Settings` consumes `coordinator.devices.devices`, `subscription`, `currentDeviceId`, `seatLimit`. `seatLimit` is only populated on 402; `DeviceVM.registerCurrent` calls `refresh()` *before* setting `seatLimit`, so if `refresh()` itself fails (network glitch) the seat-limit UI shows whatever devices list was previously loaded.

CLI also uses the devices API directly (`--token` flow) — calling `POST /api/v1/me/devices` through `CLIAPIClient` against the same server. The CLI does not maintain a "current device id" — it just registers and exits.

## Cross-cutting concerns

### Application logging

`BlikShared.AppLogger.shared` is the unified logger for GUI processes (BlikApp + BlikMenuBar). Dual sink: `os.Logger` (subsystem `com.blik.app`) **and** a one-JSON-line-per-record file at `~/Library/Logs/Blik/app.log`. Rotation at 1 MB → `app.log.old`. Singleton, `@unchecked Sendable`, file writes guarded by `NSLock`. Log records use `BlikCore.JSONLogFormatter` + `LogLevel`. `BlikHelper.HelperLogger` is a parallel implementation for the daemon (writes to `/Library/Logs/Blik/helper.log` via NSLog mirror). CLI uses its own `Sources/blik/App/Logger.swift` (CWD-relative `blik.log`, truncated on each start) — does not share with AppLogger.

### MenuBar scenes (two of them)

Both `BlikApp` and `BlikMenuBar` declare a `MenuBarExtra` scene:
- `BlikApp` ships its menubar popup inside the main GUI process (so the popup can call `@Environment(\.openWindow)` / `@Environment(\.openSettings)` directly without cross-process URL).
- `BlikMenuBar` is a separate executable for users who want only the menubar without the GUI window in the dock; it routes settings access through `blik://settings` → `BlikApp`.

Both share the same `BlikShared.AppCoordinator` type but instantiate independent coordinators (separate processes). Each holds its own XPC client and polling task.

### Settings scene (BlikApp only)

`BlikApp` uses the native macOS `Settings` SwiftUI scene with five sub-pages: Account / Devices / App / Updates / About. Access from in-app: sidebar footer button (`OpenSettingsButton`) via `@Environment(\.openSettings)`. Access from BlikMenuBar / external: `blik://settings` URL (handled via deep-link fallback — see flow 4). Legacy in-window Settings tab has been removed; `SidebarTab` no longer contains `.settings`.
