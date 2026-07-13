# BlikApp

## Purpose
SwiftUI executable that ships the main GUI for `.blik`: a `Window` with a `NavigationSplitView` (Overview / Temperature / Resources / Charts), a native `Settings` scene with two sub-pages (App / About), and a `MenuBarExtra` scene that mirrors the menubar popup. It is a thin presentation layer over `BlikShared.AppCoordinator` — owns no SMC/XPC state itself, only renders coordinator data and routes user intent (preset switches, theme/poll/launch-at-login toggles, update install, uninstall) back into the VMs.

The app is fully free: the former Account / Devices / Telemetry Settings pages, the sidebar user widget, all subscription gates, and the `navigateToSettings` notification were **removed** when the licensing server was decommissioned (2026-07-13). No auth/login/avatar/device-management UI remains; `BlikApp` has no external package dependencies (Kingfisher was dropped).

## Key files
- `Sources/BlikApp/BlikAppMain.swift` — `@main BlikAppEntry`, three SwiftUI scenes (`Window` / `Settings` / `MenuBarExtra`), `AppDelegate`, `SingleInstanceGuard`, dock icon swap
- `Sources/BlikApp/Views/MainContentView.swift` — `NavigationSplitView`, custom sidebar rows with brand-color selection fill, search field, theme, deep-link dispatch (NotificationCenter + `coordinator.pendingTab`); also declares `enum AppTheme`
- `Sources/BlikApp/Views/Overview/OverviewPage.swift` — two summary sections only: «Температура» (avg CPU P-core / E-core / GPU) + «Ресурсы» (avg CPU / E-CPU busy, GPU util, VRAM / RAM used, disk I/O rate); both render as a shared 3-column `LazyVGrid` (`gridColumns`) of unified KPI cells via `metricCell(label:value:unit:)` — uppercase label + large monospaced rounded number + small tertiary unit, neutral `.primary` color (no semantic temperature/load gradients; those live on the detail tabs). `bytesParts`/`rateParts`/`splitLastToken` split `ByteCountFormatter` output into (number, unit). Fan rows + preset control were moved to `SensorsPage`. <!-- subscription gate (gatedContent/gateBody) and `Notification.Name.navigateToSettings` removed — app is fully free -->
- `Sources/BlikApp/Views/Shared/MetricSectionListPage.swift` — shared page scaffold (search + section list) used by `SensorsPage` and `ResourcesPage`; generic over `Leading: View` <!-- auth/gating removed — pages are always live -->; — optional `@ViewBuilder` **leading** slot for extra custom sections rendered BEFORE the metric sections (convenience init with `Leading == EmptyView` for the plain case). Was `Trailing` (after); flipped so coolers/control sit at the top of the Temperature tab. All rows/headers/footers carry `.listRowSeparator(.hidden)` (only the footer spacer remains as the inter-category gap)
- `Sources/BlikApp/Views/Sensors/SensorsPage.swift` — «Температура» tab: coolers («Куллеры») and speed control («Управление») sections injected via the `MetricSectionListPage` **leading** slot (rendered at the very top, before sensor categories); sensors grouped by `SensorGroup` (mapped to `MetricSection`); in-page search filter
- `Sources/BlikApp/Views/Resources/ResourcesPage.swift` — «Ресурсы» tab: CPU per-core / RAM / GPU / disk-IO sections from `coordinator.resource` (`ResourceVM`), built on `MetricSectionListPage`
- `Sources/BlikApp/Views/Preferences/PreferencesView.swift` — root of the `Settings` scene; inner `NavigationSplitView` with two tabs and `enum PreferencesTab` (`app, about`). Inner `WindowAccessor` (`NSViewRepresentable`) grabs the hosting `NSWindow` so `centerOverMain` can position the Settings window over the main window (main found by identifier `main`, then title `.blik`, then widest visible window; fallback `settings.center()`) <!-- account / devices / telemetry / updates tabs removed; Updates folded into App/About surface -->
- `Sources/BlikApp/Views/Preferences/AppPage.swift` — appearance (theme picker), poll frequency (1/5/10s), launch-at-login toggle, daemon/helper/mode status indicators
- `Sources/BlikApp/Views/Preferences/AboutPage.swift` — app logo + version + GitHub link + uninstall (destructive `confirmationDialog`)
<!-- removed: AccountPage.swift, DevicesPage.swift, TelemetryPage.swift, Sidebar/SidebarUserWidget.swift, AvatarView — deleted with the auth/telemetry/subscription stack -->
- `Sources/BlikApp/Views/Sidebar/OpenSettingsButton.swift` — sidebar footer button, opens native `Settings` scene via `@Environment(\.openSettings)`
- `Sources/BlikApp/Views/MenuBar/MenuBarPopupView.swift` — popup body for `MenuBarExtra` scene (header + banners + fans + presets + sensors + footer); footer «Панель» (`openPanel()`) closes the `MenuBarExtra(.window)` popup via `NSApp.keyWindow?.close()` and posts `.showMainWindow` to show/activate the main window centrally
- `Sources/BlikApp/Views/MenuBar/MenuBarLabel.swift` — menubar icon image (NSImage via `MenuBarImageRenderer`)
- `Sources/BlikApp/Views/MenuBar/MenuBarFanRowView.swift`, `MenuBarSensorSectionView.swift` — popup rows
- `Sources/BlikApp/Utilities/WindowHideDelegate.swift` — close-button intercept (`orderOut` + `setActivationPolicy(.accessory)`) + min-size guard + one-shot background notification
- `Sources/BlikApp/Resources/dock_icon_{dark,light}.png` — runtime dock icon assets, swapped on theme change
- `Sources/BlikApp/Resources/sidebar_icon_{dark,light}{,@2x}.png` — sidebar icon assets (bundled, no current code references — staged for future use)

## Entry points
- `@main BlikAppEntry` — SPM executable target `BlikApp`. Three scenes declared in `body`:
  - `Window(".blik", id: "main")` — main GUI
  - `Settings { PreferencesView() }` — native Settings, auto-bound to "Blik → Settings…" menu + ⌘,
  - `MenuBarExtra { MenuBarPopupView() } label: { MenuBarLabel() }` with `.menuBarExtraStyle(.window)`
- URL scheme `blik://settings` / `blik://overview` / `blik://temperature` / `blik://resources` / `blik://charts` — handled in three places:
  - `AppDelegate.application(_:open:)` is the AppKit entry point (Apple Event arrives before SwiftUI subscribes), buffers URLs in `pendingDeepLinkURLs` and posts `Notification.Name.deepLinkReceived`
  - SwiftUI `.onOpenURL` on the `Window` (warm path → `coordinator.handleDeepLink(url)`)
  - `MainContentView.onAppear` calls `delegate.consumePendingDeepLink(into:)` for cold-start drainage
<!-- removed: Notification.Name.navigateToSettings — it was posted only from license/subscription-gate CTAs, which are gone. Settings is now reached only via OpenSettingsButton (sidebar footer) -->
- `Notification.Name.showMainWindow` (declared in `BlikAppMain.swift`) — posted by `AppDelegate.showMainWindow()` (Dock reopen handler) **and** by `MenuBarPopupView.openPanel()` (footer «Панель»); handler in `BlikAppMain`/`MainContentView` does `openWindow(id: "main")` + `activate(ignoringOtherApps:)`. Show/activate of the main window is now centralized through this notification — callers do not call `openWindow` directly
- `Notification.Name.deepLinkReceived` (declared in `BlikAppMain.swift`) — posted by `AppDelegate.application(_:open:)`, observed by the `Window` via `.onReceive` to forward to `coordinator.handleDeepLink`
- Distributed cross-process navigation (`com.blik.navigateToSettings` + `NSTemporaryDirectory/blik-navigate-to.txt`) — handled inside `BlikShared` and surfaced via `coordinator.pendingTab`; `MainContentView.onChange(of: coordinator.pendingTab)` consumes it and clears
- `coordinator.fan.shouldTerminate` — observed in `MainContentView`; flips `NSApplication.shared.terminate(nil)` to wire CLI/Update-driven shutdown into the GUI process

## Dependencies
- BlikShared — `AppCoordinator`, `FanControlVM`, `ResourceVM`, `UpdateVM`, `AppSettingsVM`, `SidebarTab` (`.overview`/`.temperature`/`.resources`/`.charts`), `MetricNameStore`, `Charts/` VMs <!-- AuthVM / DeviceVM / TelemetryCoordinator removed: auth/subscription/telemetry stack deleted -->
- BlikDesign — `BlikPageContainer`/`BlikPageMetrics`, `BlikBanner`, `BlikStatusPill`, `BlikPresetButtons`, `MenuBarImageRenderer`, `DesignTokens`, `BlikPalette`, `TemperatureColor`, `AppIcons`, `EnvironmentValues.searchQuery` + `searchVisible(matches:)` <!-- BlikSubscriptionGate no longer used here -->
- BlikCore — `Constants` (version, GitHub repo), `FanInfo`, `SensorInfo`, `SensorGroup` <!-- licenseServerURL / LicenseStatus removed -->
- System: SwiftUI (macOS 26 Liquid Glass APIs — `scrollEdgeEffectStyle`, `DefaultToolbarItem(kind: .search)`, `ToolbarSpacer`), AppKit (`NSApplication`, `NSWindow`, `CFMessagePort` for singleton), UserNotifications (background-mode toast) <!-- NSOpenPanel gone with avatar upload; Kingfisher package dependency dropped -->

## Side effects
<!-- generated, verify -->
- `CFMessagePortCreateLocal(name: "com.blik.app.singleton")` at launch — second instance calls `NSApplication.terminate(nil)` from `applicationDidFinishLaunching`
- `NSApplication.setActivationPolicy(.regular)` at launch + on `MenuBarPopupView.openPanel()` + on Dock-reopen; `.accessory` after window hide
- `NSApplication.applicationIconImage = NSImage(...)` on theme change (dock icon swap, reads `Bundle.module` resource)
- `NSWindow.delegate = WindowHideDelegate()` on the main window (assigned in `setupWindowDelegate`)
- `NSWindow.orderOut(nil)` on close click instead of close (handled by `WindowHideDelegate.windowShouldClose`)
- `UNUserNotificationCenter.requestAuthorization` + `add(request:)` once per process when window first hidden (id `blik-background-mode`)
<!-- removed: NSOpenPanel avatar picker + avatar AsyncImage HTTP GET to licenseServerURL — Account page and AvatarView deleted -->
- `@AppStorage("appTheme")` — UserDefaults read/write (`Тёмная` / `Светлая`)
- Posts local `Notification.Name.showMainWindow` <!-- navigateToSettings removed -->
- `NSApplication.terminate(nil)` from MenuBar footer "Выход" — relies on coordinator's `willTerminateNotification` observer to run SMC `restoreAutoMode` cleanup
- All fan/update mutations delegate to `AppCoordinator` VMs — no direct SMC/XPC/HTTP calls in this module (no network I/O at all now)
- No DB, no async jobs spawned here (polling tasks live in `BlikShared`)

## Invariants / assumptions
<!-- generated, verify -->
- Toolbar = system Liquid Glass (translucent), themed via the detail column only (WWDC25 "Build a SwiftUI app with the new design" canon). Rules that all proved necessary by elimination: (1) do NOT set `titlebarAppearsTransparent` — removes the glass (toolbar goes 100% transparent); (2) do NOT set `window.backgroundColor` — it paints the WHOLE window incl. the sidebar glass, breaking the sidebar; (3) do NOT use an `ignoresSafeArea` opaque `Color` under the toolbar — reads as flat/opaque, kills perceived translucency. The working approach (two parts): (a) `MainContentView.splitView` `detail:` is `ZStack { BlikPalette.bg.resolve(colorScheme).backgroundExtensionEffect(); detailView }` — `backgroundExtensionEffect()` (macOS 26) extends the themed bg into the top safe area, scoped to the detail column so the sidebar is untouched; (b) `.toolbarBackground(.hidden, for: .windowToolbar)` on the body hides the gray system toolbar material so that dark extended bg shows through → the bar blends with content (no gray strip, no hairline separator). `.hidden` alone (without the dark bg under the bar) regresses to the gray window default — both parts are required together. The search field remains as a toolbar item on its own glass capsule
- One `AppCoordinator` per process, owned by `@State` in `BlikAppEntry` and injected via `.environment(coordinator)` into all three scenes — they share the same VM instances
- Single-instance enforced via `CFMessagePort`; duplicate launches terminate themselves *after* `applicationDidFinishLaunching` runs but before they take over the activation policy
- The window stays in `.regular` activation policy while visible and switches to `.accessory` when hidden; process keeps running because `applicationShouldTerminateAfterLastWindowClosed` returns `false`
- `Settings` scene is the **only** path for app configuration in modern builds — the legacy in-window Settings tab has been removed; `MainContentView` exposes Settings **only** via `OpenSettingsButton` (sidebar footer). The `navigateToSettings` notification path was removed with the subscription gates that posted it
- Both Overview and Temperature tabs wrap content in `BlikPageContainer` and use `List { Section }` with `BlikPageMetrics.rowInsets`; same convention applies to every Preferences sub-page (App/About) — no card-style backgrounds in content layer
- Sidebar selection color uses a custom `sidebarRow` Button + `.listRowBackground` painting `DesignTokens.accent` because `controlAccentColor` is not overridable in SPM target without Asset Catalog
- Sidebar selection dims (`Color.white.opacity(0.12)` dark / `Color.black.opacity(0.08)` light) when `controlActiveState != .key` to match System Settings behavior on Cmd-Tab
- Search field is materialized as a `DefaultToolbarItem(kind: .search)` in `MainContentView.trailingSpacerItem`; this is required (per WWDC25 #323) so that `ToolbarSpacer(.fixed)` actually shifts it — `.searchable(placement: .toolbar)` alone lives on a system-managed track and ignores spacers
- Search query is exposed via `EnvironmentValues.searchQuery`; every filterable row uses `.searchVisible(matches:)` with both RU and EN keywords
- No gating: Overview, Sensors, Resources and Charts always render live (the former auth/subscription gate that switched on `coordinator.auth.state` is gone — app is fully free). MenuBar icon falls back to `MenuBarImageRenderer.image(nil, nil, nil)` rendering «— RPM  —°C» only when fan data is unavailable
- Cold-start URL handling depends on `MainContentView.onAppear` firing — `consumePendingDeepLink` drains the buffer once per appear, so duplicate `application(_:open:)` calls before the window appears are batched correctly
- `Window` SwiftUI scene does NOT support `.handlesExternalEvents` — only `.onOpenURL` works for warm-path URL routing
- `MenuBarPopupView.openPanel()` (footer "Панель") closes the popup by `NSApp.keyWindow?.close()` (the `MenuBarExtra(.window)` popup is the current key window — `.menuBarExtraStyle(.window)` has no public dismiss API) and posts `.showMainWindow`; relies on the `Window` having id `"main"` in `BlikAppEntry` and on the `.showMainWindow` handler being subscribed
- Quit from menubar relies on coordinator's `willTerminateNotification` observer to run synchronous `restoreAutoMode`; otherwise fans stay in manual
- `MenuBarPopupView` uses `BlikPresetButtons(size: .compact)` (vs `.regular` in Overview) — preset row in popup is denser than in the main window
<!-- removed: AvatarView URL-composition invariant — avatar UI deleted with the auth stack -->

## Failure hotspots
<!-- generated, verify -->
- **URL scheme cold-start race**: if `application(_:open:)` is called and the window is never created (singleton guard rejected, early termination), `pendingDeepLinkURLs` leaks and is never consumed — acceptable, but means a deep-link from MenuBar can be dropped on double-launch
- **`@State coordinator = AppCoordinator()`**: a fresh `AppCoordinator()` is created here per process; secondary previews/test harnesses that instantiate `MainContentView`/`PreferencesView` without injecting a mock coordinator will spin up real polling/XPC
- **`setupWindowDelegate` timing**: runs in `Window.onAppear` via `DispatchQueue.main.async`. If the user closes the window before that block fires, the delegate is never attached and the next close behaves system-default (quit instead of hide)
- **Theme change → dock icon swap**: depends on `Bundle.module` resource `dock_icon_{dark,light}.png` being present; missing resource silently keeps the previous icon
- **Sidebar accent on key-loss**: sidebar dims to neutral fill when window loses key focus (`controlActiveState != .key`); regression here means selection stays bright accent during Cmd-Tab and looks out of place
<!-- removed: avatar AsyncImage-offline and avatar-upload-mime hotspots — avatar UI deleted -->
- **`Settings` scene + `confirmationDialog`**: the uninstall dialog in `AboutPage` opens inside the Settings window — on macOS 26 this is fine, but moving the section into a `MenuBarExtra` would break (dialogs close the popover, see existing NSAlert workaround note in project rules)
- **`Picker(.segmented)` for `pollIntervalSeconds`** binds via closure to `coordinator.settings.pollIntervalSeconds` (TimeInterval); only the three tagged values `1/5/10` are reachable — legacy values in `UserDefaults` will not select any segment
- **Uninstall** from `AboutPage` calls `coordinator.uninstallApp()` (delegates to daemon via XPC); when daemon is missing the action silently no-ops — `AppPage` status indicators surface "Daemon: Не подключён", but `AboutPage` does not
- **MenuBar `openPanel()`** closes the current key window (the popup) before posting `.showMainWindow`; if the popup is *not* the key window (focus elsewhere), `NSApp.keyWindow?.close()` may close the wrong window or no-op. `setActivationPolicy(.regular)` runs before the window is shown — for a single frame the app may appear in Dock without a visible window
- **`coordinator.fan.shouldTerminate` → `NSApplication.terminate`** in `MainContentView.onChange`: this is a one-way kill switch from `UpdateVM`. If the trigger fires while the window is hidden in MenuBar mode, terminate still runs — relies on `willTerminateNotification` observer to clean fans
- **`MenuBarExtra(.window)` observation-tracking leak** (fixed, do not regress): `.menuBarExtraStyle(.window)` keeps `MenuBarPopupView`/`MenuBarLabel` mounted even when the popup is closed; SwiftUI re-evaluates them on every poll-tick mutation of `coordinator.fan.fans`/`sensors` (Double jitter) and `MenuBarExtra` does not release the per-render observation tracking → `ObservationRegistrar` accumulates ~2 records/sec (creeping idle CPU→54% of a core, RSS 78→416 MB over days), reproduces only main-window-closed. Guard: `MenuBarPopupView` gates body behind `@State isPresented` (closed → `Color.clear`, reads no `coordinator.*`); `MenuBarLabel` reads the quantized `coordinator.fan.menu*` projector instead of raw `fans`. Any new always-mounted menu-bar view that reads raw per-tick observables reintroduces this. See bugs/menubar-observation-tracking-leak.md
<!-- removed: DevicesPage.task and Sidebar-widget-truncation hotspots — DevicesPage and SidebarUserWidget deleted -->

## Related docs
- modules/blik-shared.md (AppCoordinator + VMs, deep-link handling, polling lifecycle)
- modules/blik-design.md (BlikPageContainer, search modifier, design tokens, MenuBarImageRenderer)
- modules/blik-xpc.md (XPC channel used indirectly via VMs)
- modules/blik-menubar.md (separate menubar-only executable that shares the same VM layer)
- decisions/fully-free-server-decommission.md
