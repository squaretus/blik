# Resource monitoring (CPU / GPU / RAM / Disk IO)

<!-- UPDATE 2026-07-13: the app went fully free and the OTLP telemetry pipeline was removed (server decommissioned). The telemetry-feeding half of this feature (MetricGroup resource families, OTLPMetricBuilder.ingest(resources:), TelemetryCoordinator.attach(resource:)) no longer exists. The resource READING + UI half — ResourceReader/ResourceUsageCalculator/ResourceModels, ResourceVM, «Ресурсы» tab, Overview summary, and local History mapping — is fully live. Telemetry-only bullets below are marked [removed]. See decisions/fully-free-server-decommission.md. -->

## Goal
Surface live system-resource usage (CPU per-core, RAM, GPU util/mem, disk IO) in a dedicated «Ресурсы» tab, reusing the temperature polling machinery rather than building a parallel one. <!-- original goal also fed the OTLP telemetry pipeline — telemetry removed 2026-07-13; resource UI/history remain -->

## Scope
- BlikCore: new `Resources/` module (`ResourceReader`, `ResourceUsageCalculator`) + `Model/ResourceModels.swift`.
- BlikXPC: `BlikHelperProtocol.readResources` + `BlikXPCClient.readResourcesSync`.
- BlikHelper: `HelperDelegate.readResources` on `smcQueue`.
- BlikShared: `ResourceVM`, `SidebarTab.resources`. <!-- [removed] telemetry MetricGroup additions, OTLPMetricBuilder.ingest(resources:), TelemetryCoordinator.attach(resource:) — telemetry stack deleted -->
- BlikApp: shared `MetricSectionListPage`, `ResourcesPage`, `MainContentView` `.resources` case; `SensorsPage` refactored onto the shared page. Overview also grew a «Ресурсы» summary section (avg CPU/E-CPU busy, GPU util, VRAM/RAM used, disk I/O) driven by `ResourceReading` computed props — see modules/blik-app.md.

## Changes
- Added: `ResourceReader` (CPU per-core via `host_processor_info`, RAM via `host_statistics64` + `hw.memsize`, GPU via IORegistry `IOAccelerator` `PerformanceStatistics`, disk IO via `IOBlockStorageDriver` `Statistics`; GPU/IO best-effort → graceful `nil`).
- Added: `ResourceUsageCalculator` — pure `(prev, curr ResourceSnapshot) → ResourceReading`: CPU%/core from tick deltas, disk rate from cumulative-byte deltas, RAM/GPU passthrough.
- Added: `ResourceSnapshot` (raw, stateless, Codable over XPC) + `ResourceReading`, `CPUCoreTicks`, `CPUCoreUsage`, `DiskIOCounters`, `DiskIORate`, `MemoryStats`, `GPUStats`.
- Added: `readResources(reply:)` XPC method — helper returns the **raw snapshot only**; the client computes the delta (stateless daemon, no per-client prev state).
- Added: `ResourceVM` (`@Observable @MainActor`) — polls via XPC or local `ResourceReader` (read-only fallback, no root needed), holds `prevSnapshot`, runs `ResourceUsageCalculator`.
- [removed] `MetricGroup` groups `cpuUsage` / `gpuUsage` / `gpuMemory` / `memoryUsage` / `diskIO` + family `.resources` — telemetry stack deleted.
- [removed] `OTLPMetricBuilder.ingest(resources:)` emitting gauges `cpu.core.*`, `cpu.usage.overall`, `gpu.usage`, `gpu.memory.*`, `memory.*`, `disk.io.*` — telemetry stack deleted.
- Added: `MetricSectionListPage` (search + section list; former auth/gating removed) — `SensorsPage` refactored onto it, `ResourcesPage` built on it.
- Modified: `MainContentView.detailView` `.resources` case, `SidebarTab` gains `.resources`.
- Modified: version bumped `2.8.4 → 2.9.0` (`Constants.appVersion` / `BlikXPCConstants.helperVersion` via `scripts/build.sh`).

## Risks
<!-- [removed] OTLPMetricBuilder.quantize unit-classification risk — telemetry stack deleted -->
- GPU/disk readers depend on IORegistry key names (`IOAccelerator` PerformanceStatistics, `IOBlockStorageDriver` Statistics) that vary by hardware/firmware — best-effort `nil` is the contract; UI/telemetry must tolerate missing series.
- Delta computed client-side: a missed poll or a `prevSnapshot` reset (sleep/wake, reconnect) yields one bogus high/zero CPU% / disk-rate sample. Calculator must guard against negative tick/byte deltas (counter reset).
- `helperVersion` bumped to 2.9.0 — clients older than the helper without `readResources` fall back to local `ResourceReader` (read-only), so a version mismatch degrades gracefully rather than breaking.

## How to test
- [ ] «Ресурсы» tab renders CPU per-core bars, RAM, GPU (when present), disk IO rates.
- [ ] On a machine without GPU/IO IORegistry keys, those sections gracefully omit (no crash, no zero-spam).
- [ ] Read-only mode (no daemon / `swift build` without PKG): tab still populates via local `ResourceReader`.
- [ ] First poll after wake/reconnect does not emit a spurious CPU% / disk-rate spike (delta guard).
<!-- [removed] telemetry OTLP-batch and quantization/dead-band checks — telemetry stack deleted -->

## Related modules
- modules/blik-core.md (ResourceReader / ResourceUsageCalculator / ResourceModels)
- modules/blik-xpc.md (readResources)
- modules/blik-helper.md (readResources on smcQueue)
- modules/blik-shared.md (ResourceVM)
- modules/blik-app.md (MetricSectionListPage, ResourcesPage)
- decisions/fully-free-server-decommission.md
