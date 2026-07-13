# BlikShared

## Purpose
`@Observable @MainActor` VM layer shared between `BlikApp` (GUI) and `BlikMenuBar`. Owns the root `AppCoordinator` and narrow VMs (`FanControlVM`, `ResourceVM`, `UpdateVM`, `AppSettingsVM`), backed by a lazy `BlikRuntime` that bootstraps either an XPC client to `BlikHelper` or a direct SMC reader. Also hosts local metric-name overrides (`MetricNameStore`) and the `Charts/` cluster. Designed so SwiftUI views in both apps consume one shared coordinator via `.environment(...)` and never talk to `BlikCore`/`BlikXPC` directly.

The app is fully free: the previous auth/OAuth/subscription stack (`AuthVM`, `OAuthClient`, `APIClient`, `KeychainStore`), the `DeviceVM` device/subscription client, the OTLP telemetry pipeline (`Telemetry/`), and the file logger `AppLogger` were **removed** when the licensing server was decommissioned (2026-07-13). No network I/O remains in this module except the GitHub-Releases update check (via `UpdateService`).

## Key files
- `Sources/BlikShared/AppCoordinator.swift`
- `Sources/BlikShared/FanControlVM.swift`
- `Sources/BlikShared/ResourceVM.swift`
- `Sources/BlikShared/UpdateVM.swift`
- `Sources/BlikShared/AppSettingsVM.swift`
- `Sources/BlikShared/BlikRuntime.swift`
- `Sources/BlikShared/LaunchAgentController.swift`
- `Sources/BlikShared/MetricNameStore.swift`
- `Sources/BlikShared/Charts/` — ChartsVM, ChartTimeRange, ChartWidgetConfig/Store, LiveMetricBuffer, MetricCatalog

## Entry points
- `AppCoordinator()` — root constructor. Builds `runtime`, then `settings`, `fan`, `resource`, `update` (the former `auth`/`devices`/`telemetry` VMs no longer exist). Registers `willTerminate` observer and observation tracking for poll interval / update termination.
- `AppCoordinator.handleDeepLink(_ url: URL)` — parses URL host/path. `blik://overview` / `blik://temperature` / `blik://resources` → sets `pendingTab`. Unknown token → falls back to `.overview` (logged). (The former `blik://auth?code=...` OAuth-callback branch was removed with the auth stack.)
- `AppCoordinator.uninstallApp()` — delegates to `fan.uninstallApp()`. (The former local Keychain wipe + `oauth.revoke` were removed with the auth stack.)
- `AppCoordinator.pendingTab: SidebarTab?` — read-and-clear channel for URL deep-link, consumed by `MainContentView`. `SidebarTab` enum has `.overview`, `.temperature`, `.resources`, and `.charts` (Settings is a separate window scene).
- `SidebarTab` enum — `public`, `Sendable`, `CaseIterable`, with `title` (RU) and `systemImage` (SF Symbol).
- `ResourceVM` (`@Observable @MainActor`) — polls a `ResourceSnapshot` (via `BlikXPCClient.readResourcesSync` when connected, else a local `BlikCore.ResourceReader` — read-only, no root needed), keeps `prevSnapshot`, and runs `ResourceUsageCalculator` to publish a `ResourceReading` (CPU%/core, RAM, GPU, disk IO rate). Shares the same polling-Task + sleep/wake-observer pattern as `FanControlVM`; `prevSnapshot` is reset on wake/reconnect so the first post-gap sample is discarded rather than emitting a spurious spike.
- `FanControlVM.setSpeedPreset(percentage:)` — 0/25/50/75/100 preset application. Mutates `fans[i].isForced` / `targetSpeed` immediately for UX feedback, then calls `helper.setFanSpeedPreset` over XPC. In read-only mode sets `errorMessage = "Режим только для чтения"`.
- `FanControlVM.restoreAutoMode()` — alias for `setSpeedPreset(percentage: 0)`.
- `FanControlVM.restartPolling()` — cancels and recreates the polling Task (no-op if `isSleeping`). Called on init, on `pollIntervalSeconds` change, and on wake.
- `FanControlVM.uninstallApp()` — XPC `uninstallAll` (or `osascript` fallback) + 6s delay + `shouldTerminate = true`. Fallback waits for `waitUntilExit` of `osascript` before setting `shouldTerminate`.
- `FanControlVM.averageChipTemp: Int` — computed average over sensors in groups `.cpuCores`, `.npuECores`, `.gpuCores`.
- `UpdateVM.checkForUpdateManually()` / `UpdateVM.installUpdate()` — forced check via `UpdateService.checkForced`, install via `helper.performUpdate` + 3s install-monitor Task that watches `xpcClient.isConnected`.
- `AppSettingsVM.refreshLaunchAtLogin()` — re-syncs `launchAtLogin` from `launchctl print gui/<uid>/...` (call on `onAppear`).
- `AppSettingsVM.canManageLaunchAtLogin: Bool` — `true` iff `/Library/LaunchAgents/com.blik.app.plist` exists.
- `LaunchAgentController.enable()` / `disable()` / `isEnabled` / `isInstalled` — sync `launchctl bootstrap` / `bootout` / `print` wrappers in user domain (`gui/<uid>`).

## Dependencies
- Library: `BlikCore` (SMC types, `FanInfo`, `SensorInfo`, `Constants`, `SemanticVersion`, `UpdateInfo`, `StateSnapshot`, `JSONLogFormatter`, `LogLevel`, History/MetricKey/MetricSample). <!-- HardwareID removed with the License/ dir; auth/telemetry no longer read it -->
- Library: `BlikXPC` (`BlikXPCClient`, `BlikHelperProtocol`, `UpdateService`).
- Frameworks: `Foundation`, `AppKit` (`NSApplication.willTerminateNotification`, `NSWorkspace.shared.notificationCenter`, `NSWorkspace.shared.open(url:)`), `os` (logging). <!-- removed: Security (Keychain), CryptoKit (PKCE), Compression (OTLP gzip), Darwin SecRandomCopyBytes — all belonged to the deleted auth/telemetry stack -->
- External binary: `/bin/launchctl` (LaunchAgentController bootstrap/bootout/print).
- External binary: `/usr/bin/osascript` (uninstall fallback in `FanControlVM.uninstallViaScript`).
- Network: none in-module except the GitHub-Releases update check routed through `BlikXPC.UpdateService` (daemon-side download/install). <!-- removed: URLSession → Constants.licenseServerURL (OAuth / devices / subscription / min-client-version / OTLP) — server decommissioned -->

## Side effects
<!-- generated, verify -->
- `UserDefaults` writes: `pollIntervalSeconds` key (`AppSettingsVM.didSet`); metric-name overrides (`MetricNameStore`, suite `com.blik.shared`, key `metricCustomNames.v1`). <!-- removed: telemetry.* keys — TelemetrySettings deleted -->
- `NotificationCenter.default` observer on `NSApplication.willTerminateNotification` (registered in `AppCoordinator.init`, removed in `deinit`).
- `NSWorkspace.shared.notificationCenter` observers on `willSleepNotification` / `didWakeNotification` (registered in `FanControlVM.init`, removed in `deinit`).
- Spawns subprocesses: `/bin/launchctl` (bootstrap/bootout/print), `/usr/bin/osascript` (uninstall fallback).
- XPC calls (via `BlikXPCClient`): `readAllFans`, `readAllSensors`, `readState`, `readResources`, `setFanSpeedPreset`, `getHelperVersion`, `performUpdate`, `uninstallAll`, `restoreAutoModeSync`, `queryHistory`, `listHistoryMetrics`. <!-- removed: validateLicense / getLicenseStatus (license XPC API gone), and all HTTP/OAuth/Keychain side effects (auth stack deleted) -->
- Forced update check inside daemon (triggered by `UpdateService.checkForced`).
- On `applicationWillTerminate`: synchronous `BlikXPCClient.restoreAutoModeSync()` + `disconnect()` to guarantee fans return to AUTO before process exit.
- Long-running `Task`s:
  - `FanControlVM.pollingTask` — sleeps for `pollIntervalSeconds`, cancelled/restarted on interval change / sleep / wake / deinit.
  - `ResourceVM.pollingTask` — same cadence/lifecycle as `FanControlVM`.
  - `UpdateVM.checkTask` — 6h periodic (`Constants.updateCheckInterval`).
  - `UpdateVM.installMonitorTask` — 3s `client.isConnected` polling during install.
  <!-- removed: DeviceVM.pollingTask, AuthVM.loginTimeoutTask, TelemetryCoordinator.flushTask/senderTask — VMs deleted -->

## Invariants / assumptions
<!-- generated, verify -->
- All `@Observable` VMs are `@MainActor`-isolated. Any XPC reply (delivered on XPC queue) in non-MainActor context must hop through `Task { @MainActor in ... }` before mutating state. Every callback in this module does the hop.
- `AppCoordinator` is constructed exactly once per process and lives the entire app lifetime. Both `BlikApp` and `BlikMenuBar` keep it as `@State` and inject via `.environment(...)`.
- `BlikRuntime.xpcClient` is decided once in `init`: either XPC `connectAndVerify()` succeeds (then `reader`/`writer` are nil) or direct read-only SMC (`reader` set, `writer` nil — direct write would require sudo + manual retry, deliberately not used in GUI). It does **not** switch at runtime.
- `BlikRuntime.supportsReadState` is set asynchronously after `init` via `getHelperVersion`; reads before the reply are `false` (safe — `FanControlVM.refreshData` falls back to split `readAllFans` + `readAllSensors`).
- `BlikRuntime.isReadOnly == (xpcClient == nil)`. In read-only mode `setSpeedPreset` always errors with «Режим только для чтения».
- `AppSettingsVM.pollIntervalSeconds` is validated against `Constants.pollIntervalOptions` in `didSet`; invalid writes are reverted to `oldValue`.
- `AppSettingsVM.launchAtLogin` mirrors `launchctl` state. On `launchctl` failure the setter rolls back the value to keep UI honest.
- `@AppStorage` cannot be used inside an `@Observable` class — `AppSettingsVM` reads/writes `UserDefaults` directly with `didSet`. `appTheme` deliberately stays as `@AppStorage` in views.
- `UpdateVM.shouldTerminate` is replicated into `FanControlVM.shouldTerminate` by `AppCoordinator.observeUpdateShouldTerminate()` so `MainContentView` watches one source of truth.
- `withObservationTracking` `onChange` fires **once** — `observePollInterval`, `observeUpdateShouldTerminate` re-subscribe themselves recursively from inside the closure. <!-- removed: observeAuthChanges (auth stack deleted) -->
- `pendingTab` is set by the coordinator and cleared by the view (read-and-clear semantics).
- `Notification` is not `Sendable` under Swift 6 — sleep/wake observers use stored `NSObjectProtocol` tokens with `addObserver(forName:object:queue:using:)`, never `AsyncSequence` form.
- `FanControlVM.applyUpdate` skips state writes when arrays are equal — avoids spurious SwiftUI re-renders.
- `FanControlVM.menuFan0RPM`/`menuFan1RPM`/`menuChipTemp` are a **quantized Int projection** of `fans`/`sensors` for the always-live menu-bar icon. `updateMenuProjection` (called from `applyUpdate`) writes them **only when the displayed value changes**, so observers (`MenuBarLabel`) re-render every few seconds instead of every poll tick. The menu-bar label must read these projectors, never raw `fans`/`averageChipTemp` — reading raw observables from an always-mounted `MenuBarExtra(.window)` view reintroduces the observation-tracking leak. See bugs/menubar-observation-tracking-leak.md.
- `FanControlVM` and `UpdateVM` carry **injectable watchdog timeouts** (`unlockTimeout` default 30 s; `installTimeoutSeconds` default 300 s) so a lost XPC reply cannot pin a spinner (and its active display-cycle) forever. `BlikRuntime` has a test-only `init(xpcClient:reader:writer:...)` for mock injection. Tests pass small thresholds.

## Failure hotspots
<!-- generated, verify -->
- XPC reply hopping: forgetting `Task { @MainActor in ... }` inside an XPC callback causes either a runtime crash (Swift 6 isolation) or stale UI (write on background actor). Every helper closure here does the hop.
- `pollingTask` lifecycle around sleep/wake: if `pauseForSleep` and `restartPolling` race (e.g. wake fires before `isSleeping = true` is committed), polling can stay paused. Current implementation pauses synchronously on the main queue, which the observers are registered on.
- `BlikRuntime.cleanup` must run synchronously from `willTerminate` — if `restoreAutoModeSync` returns slowly, the process may still exit before fans return to AUTO. The 5s reinforcement loop inside `BlikHelper` is the backstop.
- `LaunchAgentController.isEnabled` runs `launchctl print gui/<uid>/...`; if the agent is loaded in a different domain (root, system) the check returns false and UI shows a wrong-but-consistent state. Process termination status is the sole signal — stdout/stderr are piped and ignored.
- `pollIntervalSeconds` setter validates against `Constants.pollIntervalOptions`; stored values outside the list silently fall back to `defaultPollIntervalSeconds` on next launch.
- `installMonitorTask` in `UpdateVM` polls `client.isConnected` every 3s — if the daemon does a fast bootout/bootstrap that completes inside one window, the disconnect signal may be missed. The `performUpdate` reply also triggers `shouldTerminate`, so both paths converge. If neither reply nor disconnect arrives within `installTimeoutSeconds` (default 300 s) a watchdog clears `isInstallingUpdate` so the spinner (and its display-cycle) cannot hang forever.
- Deep-link parser falls back to `.overview` for any unrecognised host/path. Unknown links are not surfaced to the user beyond the log line.
- `uninstallViaScript` blindly copies `uninstall-helper.sh` from the app bundle to `/tmp/`. If the bundle is read-only or the resource is missing, error is reported via `errorMessage`; if the script itself fails inside `osascript`, only the launch failure is caught — script-internal failures are silent.

## Related docs
- modules/blik-core.md
- modules/blik-xpc.md
- modules/blik-helper.md
- modules/blik-app.md
- modules/blik-menubar.md
- decisions/fully-free-server-decommission.md
