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

## If idle CPU/RAM of Blik.app creeps up over hours/days (menu-bar-only, main window closed) — see MenuBarExtra observation-tracking leak
- Diagnose: `sample <pid>` shows continuous CA display-cycle + `ObservationRegistrar.registerTracking/cancel` + `AnyKeyPath.hash` churn; `heap <pid> | grep ObservationRegistrar` count grows ~2/sec (fresh process ~35, flat).
- `Sources/BlikApp/Views/MenuBar/MenuBarPopupView.swift` (`isPresented` gate, `.onAppear`/`.onDisappear`)
- `Sources/BlikApp/Views/MenuBar/MenuBarLabel.swift` (reads `menu*` projector, not raw `fans`)
- `Sources/BlikShared/FanControlVM.swift` (`updateMenuProjection`, quantized `menu*` projectors)
- Sibling pins of an active display-cycle: `FanControlVM.isUnlocking` watchdog, `UpdateVM.monitorInstall` watchdog <!-- former TelemetryCoordinator.observeEnabled/observeEnabledGroups pin removed with the telemetry stack -->
- bugs/menubar-observation-tracking-leak.md
