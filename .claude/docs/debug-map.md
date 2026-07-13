# Debug Map

<!-- HISTORICAL: the telemetry (OTLP) pipeline was removed 2026-07-13 when the app went fully free and the server was decommissioned. `Sources/BlikShared/Telemetry/*` no longer exists; the two symptoms below can no longer occur in current builds. The bug docs are kept as history. See decisions/fully-free-server-decommission.md. -->
## [HISTORICAL] If telemetry backlog never shrinks after network recovery — see TelemetrySender drain loop
- (removed) `Sources/BlikShared/Telemetry/TelemetrySender.swift` (`runLoop`, `drainReady`)
- (removed) `Sources/BlikShared/Telemetry/TelemetryBuffer.swift` (`nextReady`, `ackSuccess`, `ackFailure`)
- bugs/telemetry-backlog-stuck.md (history)

## [HISTORICAL] If OTLP telemetry returns 429 in bursts / device hits per-device rate limit — see TelemetrySender throttle gate
- (removed) `Sources/BlikShared/Telemetry/TelemetrySender.swift` (`drainReady`, `tryFlushOne`, `sendBatch`, `parseRetryAfter`, `blockedUntil`)
- (removed) `backend/app/services/throttle.py` (`otlp_ingest_limiter`, 60 req/min per device)
- bugs/telemetry-rate-limit-burst.md (history)

## If Charts show «История недоступна: хелпер не установлен или устарел» while the helper is installed (Settings says «Установлен»), or live polling lags after a release — see release-version-vs-protocol gate mismatch
- Mechanism: `build.sh` used to stamp the marketing release version into `XPCConstants.helperVersion`; the client's `minHelperVersionFor*` gates compare against that same value. A release version below a gate makes a fresh helper fail its own gates → empty-state history + legacy double round-trip live polling.
- `Sources/BlikXPC/XPCConstants.swift` (`protocolVersion` — must be a protocol level, NOT the release version; `build.sh` must not `sed` it)
- `Sources/BlikCore/Constants.swift` (`minHelperVersionForReadState`, `minHelperVersionForHistory` — never above current `protocolVersion`)
- `scripts/build.sh` (must not substitute into `XPCConstants.swift`)
- Check: `FanControlVM.refreshData()` legacy path (`readAllFans` + `readAllSensors`) means `supportsReadState` is false; `BlikRuntime.helperSupportsHistory` false → empty charts. Settings status only probes XPC connection, not gates — misleading.
- bugs/release-version-vs-protocol-gates.md

## If a live Charts window is near-empty / X-axis collapsed on 5 or 15 min while 30 min+ is fine — see live narrow-window history backfill
- Mechanism: narrow live windows (≤ buffer span, 900 s) used to draw ONLY from the in-memory `LiveMetricBuffer` (fills only while page visible); daemon history was gated to windows wider than the buffer, so a fresh page had a thin/stale buffer and `MetricChart.window` clamped the left axis to available data. Fix pulls history for ANY live window and merges history + live buffer tail.
- `Sources/BlikShared/Charts/ChartsVM.swift` (`restartLiveHistory` — gate now only `helperSupportsHistory` + `xpcClient`; `liveMergeSplit(history:bufferSegments:)`; `liveBufferSpan` removed)
- `Sources/BlikApp/Views/Charts/ChartFormatting.swift` (`ChartData.segments` live branch — buffer-only only when history absent, else merge history + tail)
- Check: `liveHistory[metric]` empty ⇒ helper unavailable or history not yet loaded (buffer-only fallback); stale buffer fragments are dropped by `liveMergeSplit` (keeps last contiguous segment as tail).
- bugs/live-narrow-window-empty-charts.md

## If idle CPU/RAM of Blik.app creeps up over hours/days (menu-bar-only, main window closed) — see MenuBarExtra observation-tracking leak
- Diagnose: `sample <pid>` shows continuous CA display-cycle + `ObservationRegistrar.registerTracking/cancel` + `AnyKeyPath.hash` churn; `heap <pid> | grep ObservationRegistrar` count grows ~2/sec (fresh process ~35, flat).
- `Sources/BlikApp/Views/MenuBar/MenuBarPopupView.swift` (`isPresented` gate, `.onAppear`/`.onDisappear`)
- `Sources/BlikApp/Views/MenuBar/MenuBarLabel.swift` (reads `menu*` projector, not raw `fans`)
- `Sources/BlikShared/FanControlVM.swift` (`updateMenuProjection`, quantized `menu*` projectors)
- Sibling pins of an active display-cycle: `FanControlVM.isUnlocking` watchdog, `UpdateVM.monitorInstall` watchdog <!-- former TelemetryCoordinator.observeEnabled/observeEnabledGroups pin removed with the telemetry stack -->
- bugs/menubar-observation-tracking-leak.md
