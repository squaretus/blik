# BlikMenuBar

## Purpose
Standalone SwiftUI `MenuBarExtra` executable that lives in the macOS menu bar as an accessory app (no Dock icon, no main window). Renders fan RPM + averaged chip temperature as the menu bar item and exposes a 340pt popup with fan rows, preset buttons, sensors, update banner and footer with cross-process links into `BlikApp`. Runs in its own process, separate from `BlikApp`, and shares a single `BlikShared.AppCoordinator` instance held in `@State` on the `App` struct. All SMC / update work is delegated to the daemon over XPC through the coordinator's VMs.

The app is fully free: the former subscription gate (`gateBody`, `BlikSubscriptionGate`) and the `MenuBarLabel` subscription branch were **removed** when the licensing server was decommissioned (2026-07-13). The popup body and the menu-bar label are now unconditional (no `DeviceVM.subscriptionState` switch).

## Key files
- `Sources/BlikMenuBar/BlikMenuBarApp.swift`
- `Sources/BlikMenuBar/MenuBarLabel.swift`
- `Sources/BlikMenuBar/FanDetailView.swift`
- `Sources/BlikMenuBar/FanRowView.swift`
- `Sources/BlikMenuBar/SensorSectionView.swift`

## Entry points
- `@main BlikMenuBarApp` — `App` scene composed of a single `MenuBarExtra { FanDetailView } label: { MenuBarLabel }` with `.menuBarExtraStyle(.window)`. Popup body is fixed at `width: 340`.
- `BlikMenuBarApp.init()` — runs `SingleInstanceGuard.acquire()`; on failure schedules `NSApplication.shared.terminate(nil)` on the main queue. Sets `NSApplication.shared.setActivationPolicy(.accessory)` (was previously in `SMCViewModel.init` before `@Observable` migration).
- `SingleInstanceGuard.acquire() -> Bool` — `CFMessagePortCreateLocal` on the named port `com.blik.menubar.singleton`. Returns `true` only if this is the first process to claim the port.
- `FanDetailView.body` — header + fan/preset/sensor content, unconditionally. <!-- former `validBody`/`gateBody` subscription switch removed -->
- `FanDetailView.openPanel()` — opens `/Applications/Blik.app` via `NSWorkspace`, or falls back to a sibling `BlikApp` binary next to `Bundle.main.bundlePath` for dev runs (`Process.launchedProcess`).
- `FanDetailView.openSettings()` — `NSWorkspace.shared.open(URL("blik://settings"))`.
- `MenuBarLabel.body` — two-way switch: not connected → `Text(".blik: —")`; connected → `MenuBarImageRenderer.image(fan0:fan1:temp:)` rendered NSImage. <!-- former subscription-inactive placeholder branch removed -->
- `FanRowView(fan: FanInfo)` — title `Fan {id}`, monospaced `{rpm} RPM`, MANUAL/AUTO pill, `ProgressView(actualSpeed / maximumSpeed)` tinted green/amber/red at 0.5 / 0.8 ratio thresholds.
- `SensorSectionView(group: SensorGroup, sensors: [SensorInfo])` — section title + `avg %.0f°C`, 2-column `LazyVGrid` of `name → temp` rows, per-cell color via `temperatureColor` (<60 green, 60–84 orange, ≥85 red).

## Dependencies
- BlikCore: `FanInfo`, `SensorInfo`, `SensorGroup`.
- BlikShared: `AppCoordinator` (root `@Observable`), `FanControlVM`, `UpdateVM`. <!-- DeviceVM removed with the subscription stack -->
- BlikDesign: `DesignTokens`, `BlikBanner`, `BlikPresetButtons`, `MenuBarImageRenderer`. <!-- BlikSubscriptionGate removed -->
- AppKit / Foundation: `NSApplication`, `NSWorkspace`, `Process`, `FileManager`, `CFMessagePort`, `URL`.
- BlikHelper (transitive, via `AppCoordinator` → XPC): SMC reads/writes, update check + install. <!-- subscription/device status gone -->
- External process: `BlikApp` — opened via `/Applications/Blik.app` bundle path or sibling dev binary; cross-process navigation to its Settings tab via `blik://settings` URL scheme.

## Side effects
<!-- generated, verify -->
- `BlikMenuBarApp.init` sets `NSApplication.activationPolicy = .accessory` → hides Dock icon for the whole process lifetime.
- Creates a local `CFMessagePort` named `com.blik.menubar.singleton`. The port is held in the `SingleInstanceGuard` instance and lives for the lifetime of the process (no explicit invalidation registered).
- If `SingleInstanceGuard.acquire()` returns `false`, calls `NSApplication.shared.terminate(nil)` from the main queue inside `init`.
- "Открыть панель" footer button: `NSWorkspace.shared.open(/Applications/Blik.app)` if it exists, otherwise `Process.launchedProcess(launchPath: <bundlePath>/../BlikApp, arguments: [])` for dev. Spawns or activates a second process.
- "Настройки" footer CTA: `NSWorkspace.shared.open(URL("blik://settings"))`. Handled on the `BlikApp` side by `AppDelegate.application(_:open:)` + `.onOpenURL` on the `Window` scene. <!-- was on the license gate; gate removed, CTA now in footer -->
- "Выход" footer button: `NSApplication.shared.terminate(nil)`. Triggers `willTerminateNotification`, which the coordinator observes in BlikShared to run synchronous `restoreAutoMode` cleanup before exit.
- "Обновить" banner button: `coordinator.update.installUpdate()` → XPC `performUpdate` on the daemon, which downloads the PKG and runs `installer -pkg /tmp/blik-update.pkg -target /`.
- Preset buttons (`BlikPresetButtons`): `coordinator.fan.setSpeedPreset(percentage:)` → XPC writes to `Ftst`, `F{n}Md`, `F{n}Tg` SMC keys on the daemon side.
- Reads `coordinator.fan.*`, `coordinator.update.*` on each SwiftUI re-render. <!-- coordinator.license.* / .devices.* gone -->  The polling Task and sleep/wake observers live in `FanControlVM` (BlikShared); this module is a pure consumer.
- No filesystem writes, no logging from this module directly — logs come from BlikShared (`os.Logger` subsystem `com.blik.menubar`) and the daemon.

## Invariants / assumptions
<!-- generated, verify -->
- Exactly one `BlikMenuBarApp` process per user session. Enforced by `SingleInstanceGuard`. PKG-installed copy is launched by `LaunchAgents`; manual launches from terminal/Xcode while another instance runs self-terminate immediately.
- `AppCoordinator` is constructed once via `@State private var coordinator = AppCoordinator()` and injected into both `FanDetailView` and `MenuBarLabel` via `.environment(coordinator)`. Both views observe the same `@Observable` instance — separate `@StateObject`-style copies do not exist.
- Popup width is hard-coded at `340pt` (`.frame(width: 340)`). `BlikPresetButtons` is rendered with `size: .compact`.
- Menu bar label has two mutually exclusive rendering states based on coordinator flags: `!coordinator.fan.isConnected` → text fallback `.blik: —`; connected → live RPM + averaged chip temp. <!-- former subscription-inactive placeholder state removed -->
<!-- removed: subscription-gate-replaces-body invariant — gate deleted, popup body is always the fan/preset/sensor content -->
- Preset row is hidden entirely when `coordinator.fan.isReadOnly == true` and is `.disabled` while `coordinator.fan.isUnlocking == true`.
- `BlikMenuBar` and `BlikApp` are separate processes — they share state only through the daemon (XPC) and `blik://` URL scheme. There is no IPC between the two SwiftUI processes other than the URL open call.
- All numeric labels use `Text(verbatim:)` or `String(format:)` to bypass locale grouping (RPM, °C). Direct `Text("\(Int)")` is avoided.
- `MenuBarExtra` is `.menuBarExtraStyle(.window)` — popup is an `NSPanel`-backed surface, not a menu. `SwiftUI .alert` modifier dismisses the popup; this module avoids `.alert` entirely.

## Failure hotspots
<!-- generated, verify -->
- **SwiftUI `.alert` inside `MenuBarExtra(.window)` dismisses the popup.** Any future confirmation UI must use `NSAlert` (modal off the key window) or inline `BlikBanner` rows. The current code carries no `.alert` modifier; regressions here are silent.
- **Cross-process navigation to BlikApp Settings** has two failure modes:
  - `openPanel()` silently no-ops if neither `/Applications/Blik.app` nor the sibling dev `BlikApp` binary exist.
  - `openSettings()` relies on `blik://settings` being registered in `BlikApp`'s `Info.plist` (`CFBundleURLTypes`) and handled by `AppDelegate.application(_:open:)` + `.onOpenURL` on the `Window` scene. `Window` does **not** honour `.handlesExternalEvents` — only `.onOpenURL` works. Note: `CLAUDE.md` also mentions a `DistributedNotificationCenter`/file-flag channel (`com.blik.navigateToSettings`, `NSTemporaryDirectory/blik-navigate-to.txt`); current `FanDetailView.openSettings()` uses only the URL scheme — the notification/file-flag path is not invoked from this module.
- **Singleton guard race**: `CFMessagePortCreateLocal` non-nil means "we are the single instance". The port is never explicitly invalidated; relies on process exit to release. After a crash, macOS should reap the port, but edge cases (suspended process, stale port) are not handled.
<!-- removed: subscription-state-transition hotspot (validBody↔gateBody swap) — gate deleted, popup body is stable -->
- **XPC callbacks → `@Observable` mutation**: the underlying VMs in BlikShared must hop to `@MainActor` before mutating fans/sensors/update state. Missing hop causes SwiftUI to diff on a non-main thread → crash. The bug surface lives in BlikShared, but the visible symptom (menu bar label glitch, popup freeze) shows up here.
- **`Text(verbatim:)` in `FanRowView`** prevents locale-formatted RPM (e.g. `4 000` in ru-RU). Future refactors that drop `verbatim:` will silently re-introduce locale grouping.
- **Update install side effect** runs entirely in the daemon. The popup shows `ProgressView` while `coordinator.update.isInstallingUpdate` is true; if the daemon dies mid-install, the flag may never flip back to `false` and the UI stays stuck on "Установка обновления...". No timeout / retry is implemented in this module.
- **`menuBarExtraStyle(.window)` redraw cost**: the popup re-renders on every coordinator change. Heavy work inside `body` (e.g. building large sensor grids) runs on every poll tick. `SensorSectionView` uses `LazyVGrid` to mitigate, but adding `O(n)` non-lazy work is risky.
- **Footer "Открыть панель" button uses `.buttonStyle(.plain)`** with a manual `RoundedRectangle` background and white text — does not pick up the global `.tint(DesignTokens.accent)`. Per `CLAUDE.md` convention all action buttons should be `.buttonStyle(.borderedProminent)`; this footer is an intentional exception (visual hierarchy with the secondary "Выход" button) and should not be "fixed" by reflex.

## Related docs
- modules/blik-shared.md — `AppCoordinator`, `FanControlVM`, `UpdateVM` (state lives there, not here).
- modules/blik-design.md — `BlikBanner`, `BlikPresetButtons`, `MenuBarImageRenderer`, `DesignTokens`.
- modules/blik-app.md — receiver of the `blik://settings` URL scheme; second SwiftUI process.
- modules/blik-helper.md — XPC peer behind preset writes and update install.
- modules/blik-xpc.md — protocol definitions used transitively via `AppCoordinator`.
- decisions/fully-free-server-decommission.md
