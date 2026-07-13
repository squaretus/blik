# MenuBarExtra(.window) observation-tracking leak — creeping idle CPU/RAM

## Symptoms
- Idle CPU of `Blik.app` creeps from ~0% to ~54% of one core over days.
- RSS creeps from ~78 MB to ~416 MB over the same window.
- Only reproduces when the **main window is closed** (menu-bar-only mode). With an
  ordinary SwiftUI `Window` (Overview/Resources pages) open, growth does not happen.
- `sample <pid>` shows a continuous Core Animation display-cycle plus
  `ObservationRegistrar.registerTracking` / `cancel` + `AnyKeyPath.hash` churn that
  never quiesces.

## Scope
- `BlikApp` MenuBar views (`MenuBarPopupView`, `MenuBarLabel`).
- `BlikShared` VM layer (`FanControlVM`) as the source of the per-tick observable churn.

## Root cause
`.menuBarExtraStyle(.window)` (in `BlikAppMain.swift`) keeps the popup content
(`MenuBarPopupView` → sensor/fan rows) mounted even when the popup is **closed**.
SwiftUI re-evaluates that mounted body on every change to the observed
`coordinator.fan.fans` / `coordinator.fan.sensors`, which mutate every poll tick
(1 Hz) because RPM/temperature carry `Double` jitter. `MenuBarExtra` does **not**
release the per-render observation tracking between re-renders, so
`ObservationRegistrar` accumulates ~1–2 tracking records/sec. Hashing over the
ever-growing `Set<AnyKeyPath>` is the creeping CPU; the retained
`ObservationRegistrar.State` objects are the creeping RSS. Ordinary `Window` scenes
release tracking normally and are not implicated.

## Reproduction
1. Install/run a baseline build, close the main window (menu-bar-only).
2. Leave data flowing (fans/sensors polling at 1 Hz) for tens of minutes.
3. `heap <pid> | grep ObservationRegistrar` → tracking-object count grows ~2/sec
   (observed ~24 000 after days); a freshly launched process sits at ~35 and is flat.

## Fix
Three coordinated changes break the per-tick read of raw observables by the
always-mounted menu-bar content:
1. `Sources/BlikApp/Views/MenuBar/MenuBarPopupView.swift` — `@State isPresented`
   gate with `.onAppear`/`.onDisappear`. While the popup is closed the body renders
   `Color.clear` and reads no `coordinator.*` → no per-tick observation registration.
2. `Sources/BlikShared/FanControlVM.swift` — quantized projector
   `menuFan0RPM` / `menuFan1RPM` / `menuChipTemp` (Int), written in `updateMenuProjection`
   from `applyUpdate` **only when the displayed value actually changes**.
3. `Sources/BlikApp/Views/MenuBar/MenuBarLabel.swift` — reads the projector instead
   of raw `fans` / `averageChipTemp`, so the always-live status item re-renders only
   when the displayed number changes (every few seconds), not every poll tick.

Same-branch hardening that removes other ways to pin an active display-cycle / leak
observers (smaller scale):
- `TelemetryCoordinator.observeEnabled` / `observeEnabledGroups` split into two
  self-re-arming observers (was one function re-arming both → duplicate
  subscriptions accumulating in `ObservationRegistrar` on every toggle).
- `FanControlVM` `isUnlocking` watchdog (30 s, injectable) — a lost
  `setFanSpeedPreset` XPC reply could otherwise pin the spinner and display-cycle forever.
- `UpdateVM.monitorInstall` watchdog (300 s, injectable) — a stuck install could pin
  the "Установка обновления…" spinner and a perpetual 3 s poll.
- `OTLPMetricBuilder.snapshotAndReset` stale-series pruning — dead-band state
  (`lastSentValue`/`heldPoint`) no longer grows unbounded when disks/sensors change.

## Regression checks
- [ ] `heap <pid> | grep AnyKeyPath` tracking-set count stays flat (~35) over 10+ min
      of active data flow with the main window closed (vs +2/sec baseline).
- [ ] `MenuBarLabel` re-renders only on displayed-value change, not per poll tick.
- [ ] Opening the popup still shows live fans/sensors (gate flips on `.onAppear`).
- [ ] `TelemetryCoordinator.builderRebuildCount` increments by exactly 1 per
      `enabledGroups` toggle (no duplicate observer subscriptions).

## Related files
- `Sources/BlikApp/Views/MenuBar/MenuBarPopupView.swift`
- `Sources/BlikApp/Views/MenuBar/MenuBarLabel.swift`
- `Sources/BlikShared/FanControlVM.swift`
- `Sources/BlikShared/Telemetry/TelemetryCoordinator.swift`
- `Sources/BlikShared/Telemetry/OTLPMetricBuilder.swift`
- `Sources/BlikShared/UpdateVM.swift`
