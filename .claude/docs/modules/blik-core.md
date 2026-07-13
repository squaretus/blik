# BlikCore

## Purpose
Foundation library for the whole Blik stack. Owns three concerns: (1) low-level SMC access over IOKit's `AppleSMC` connector — binary protocol, format conversions (FPE2/SP78/FLT/4CC), connection lifecycle, fan reads/writes; (2) domain models shared across all targets (`FanInfo`, `SensorInfo`, `AppState`, `StateSnapshot`, `SemanticVersion`, `UpdateInfo`, `ResourceModels`); (3) local metric History (SQLite: `MetricKey`, `MetricSample`, `MetricSampleMapper`, `HistoryQuery`, `HistoryStore`). Plus a unified JSON log formatter (`JSONLogFormatter`) consumed by daemon/CLI/UI loggers. Links system `libsqlite3`; otherwise zero SPM dependencies — `Foundation` + `IOKit`. Consumed by every executable (`blik`, `BlikApp`, `BlikMenuBar`, `BlikHelper`) and by libraries `BlikXPC` / `BlikShared`. <!-- The whole License/ dir (incl. HardwareID, LicenseChecker, LicenseStatus) was removed when the app went fully free (2026-07-13): no license validation, no hardware identity, no licenseServerURL/telemetry constants. -->-

## Key files
- `Sources/BlikCore/SMC/SMCTypes.swift` — `SMCFormat` (FPE2/SP78/FLT/fourCharCode), `SMCBytes` typealias + `smcBytesZero`, `SMCParamStruct` (80-byte kernel struct matching `AppleSMC`), nested `SMCKeyData_*` structs, `SMCSelector` (2/5/6/8/9), `Double.clamped(to:)`, `SMCError`
- `Sources/BlikCore/SMC/SMCConnection.swift` — `SMCConnection` class wrapping `io_connect_t`; `callSMC`, `readKeyInfo`, `readKey`, `writeKey`
- `Sources/BlikCore/SMC/SMCReader.swift` — `SMCReader`: `readFanCount`/`readFanSpeed`/`readFanMinSpeed`/`readFanMaxSpeed`/`readFanTargetSpeed`/`readFanMode`/`readAllFans`/`readTemperature`/`readAllSensors`, static `knownSensors` table (~80 keys: P/E cores, GPU zones, batteries, SSDs, palm rests, Intel fallbacks)
- `Sources/BlikCore/SMC/SMCWriter.swift` — `SMCWriter`: `ensureUnlocked` (Ftst=1 + 5s sleep), `setFanSpeed`, `reinforceSpeed` (non-throwing wrapper for reinforce timer), `setForcedMode` (with 5-attempt retry), `setAllFansSpeed` (preset entry point), `restoreAutoMode`, `modifiedFanIds`
- `Sources/BlikCore/Model/FanInfo.swift` — `FanInfo` (Codable, Equatable; `id`, `actualSpeed`, `minimumSpeed`, `maximumSpeed`, `targetSpeed`, `isForced`)
- `Sources/BlikCore/Model/SensorInfo.swift` — `SensorGroup` (cpuCores/npuECores/gpuCores/other; Codable, Comparable, CaseIterable; Russian `title`), `SensorInfo` (Codable), `AppState` (CLI/UI presentation state including `isUnlocking`, `updateAvailable`) <!-- licenseWarning field gone with licensing removal -->)
- `Sources/BlikCore/Model/StateSnapshot.swift` — `StateSnapshot { fans, sensors }` (Codable bundle used by XPC `readState`)
- `Sources/BlikCore/Model/ResourceModels.swift` — `ResourceSnapshot` (raw point-in-time counters: CPU per-core ticks, mem stats, GPU stats, cumulative disk-IO bytes; Codable, sent verbatim over XPC) + `ResourceReading` (computed: `CPUCoreUsage[]`, `DiskIORate`, `MemoryStats`, `GPUStats`; plus presentation-oriented computed props `averagePerformanceBusy` / `averageEfficiencyBusy` / `totalDiskBytesPerSec` used by the Overview «Ресурсы» summary), supporting `CPUCoreTicks`, `CPUCoreUsage`, `DiskIOCounters`, `DiskIORate`, `MemoryStats`, `GPUStats` (all Codable)
- `Sources/BlikCore/Model/UpdateInfo.swift` — `SemanticVersion` (Comparable, parses `X.Y.Z`), `UpdateInfo` (Codable)
- `Sources/BlikCore/Resources/ResourceReader.swift` — `ResourceReader`: best-effort point-in-time reads. CPU per-core ticks via `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`; per-core P/E type comes from `CPUTopology` (cached in a `static let topology = CPUTopologyDetector.detect()`), NOT from the old `i < eCount` numbering assumption; RAM via `host_statistics64(HOST_VM_INFO64)` + `sysctlbyname("hw.memsize")`; GPU util/mem via IORegistry `IOAccelerator` `PerformanceStatistics`; disk IO via `IOBlockStorageDriver` `Statistics`. GPU/IO are optional → graceful `nil` when keys absent.
- `Sources/BlikCore/Resources/ResourceUsageCalculator.swift` — pure caseless function: `(prev, curr ResourceSnapshot) → ResourceReading`. CPU%/core from tick deltas, disk read/write rate from cumulative-byte deltas, RAM/GPU passthrough.
- `Sources/BlikCore/Resources/CPUTopology.swift` — `CPUTopology` (logical CPU index → `CPUCoreType` map; `type(for:)` defaults unknown index to `.performance`) + pure builders `from(entries:)` / `uniform(logicalCount:)`. `CPUTopologyDetector.detect()` reads IODeviceTree `/cpus/*` `cluster-type` (prefix `E` → efficiency) + `logical-cpu-id` per core; Intel Mac / device-tree without cluster-type → `uniform` (all performance); Linux is a TODO (sysfs `cpu_capacity`, not yet implemented).
<!-- removed: entire `Sources/BlikCore/License/` dir — `LicenseStatus.swift`, `LicenseChecker.swift`, `HardwareID.swift` all deleted when the app went fully free (2026-07-13) -->
- `Sources/BlikCore/Logging/JSONLogFormatter.swift` — `LogLevel` enum + caseless `JSONLogFormatter`; emits one JSON object per line with ISO-8601 ms timestamp, sanitizes `pat_…` / JWT (`eyJ…`, >40 chars), helpers `truncateID`/`maskEmail`
- `Sources/BlikCore/Constants.swift` — single `Constants` namespace: poll/UI tunables, fan presets `[0,25,50,75,100]`, `ftstUnlockDelay = 3.0`, `appVersion` (rewritten by `scripts/build.sh`), `minHelperVersionForReadState`, `minHelperVersionForHistory`, GitHub repo coords (`githubOwner = "squaretus"`, `githubRepo = "blik"`), update check intervals, `pollIntervalOptions`, history tunables (`historyRawCadenceSeconds`, `historyRawRetention`, `historyRollupRetention`, `historyRawQueryWindow`, `historyDBPath`). <!-- removed: licenseServerURL, all telemetry OTLP tunables, and the old license constants — app is fully free, server decommissioned -->

## Entry points
SMC:
- `SMCConnection() throws` — opens `AppleSMC`, throws `SMCError.serviceNotFound` / `.connectionFailed`
- `SMCConnection.callSMC(input:) throws → SMCParamStruct` — raw kernel call via selector 2 (`kSMCHandleYPCEvent`)
- `SMCConnection.readKeyInfo(key:) throws → SMCKeyData_keyInfo_t`
- `SMCConnection.readKey(_ keyStr:) throws → (bytes: SMCBytes, dataSize: UInt32, dataType: UInt32)`
- `SMCConnection.writeKey(_ keyStr:, dataType:, bytes:, dataSize:) throws` — internally calls `readKeyInfo` first to populate `dataAttributes`
- `SMCReader(connection:).readFanCount() throws → Int` (reads `FNum`)
- `SMCReader.readFanSpeed/readFanMinSpeed/readFanMaxSpeed/readFanTargetSpeed(fan:) throws → Double` — reads `F{n}{Ac|Mn|Mx|Tg}`, dispatches on `dataType` (FLT vs FPE2)
- `SMCReader.readFanMode(fan:) → Bool` — non-throwing; reads `F{n}Md`, returns `true` only when byte == 1
- `SMCReader.readAllFans() throws → [FanInfo]`
- `SMCReader.readTemperature(key:) → Double?` — auto-detects FLT vs SP78 via `dataType`, filters `0 < value < 150`
- `SMCReader.readAllSensors() throws → [SensorInfo]` — iterates `knownSensors`, returns successful reads sorted by group rawValue
- `SMCReader.knownSensors: [(key, name, group)]` — static probe table
- `SMCWriter(connection:, log:)` — `log` closure injected (defaults to no-op)
- `SMCWriter.setFanSpeed(fan:, rpm:) throws` — writes `F{n}Tg` in detected data type (FLT or FPE2)
- `SMCWriter.reinforceSpeed(fan:, rpm:)` — non-throwing variant for 1Hz reinforce timer
- `SMCWriter.setForcedMode(fan:, enabled:) throws` — on enable: `ensureUnlocked` + 5 retries with 2s sleep on `F{n}Md=1`
- `SMCWriter.setAllFansSpeed(percentage:, fans:) throws` — preset entry; `percentage == 0` → `restoreAutoMode`; otherwise `min + (max - min) * pct/100` per fan, sets forced mode if not already
- `SMCWriter.restoreAutoMode(fanCount: Int? = nil)` — writes `F{n}Md=0` for all fans (only if `ftstUnlocked`), then `Ftst=0`; defaults `fanCount` to `(modifiedFans.max() + 1) ?? 2`
- `SMCWriter.modifiedFanIds: Set<Int>` — read-only view of fans the writer touched in this session
- `SMCFormat.fourCharCode(_:) / fourCharCodeToString(_:)`
- `SMCFormat.fpe2ToDouble / doubleToFpe2` (big-endian 14.2 fixed)
- `SMCFormat.sp78ToDouble` (big-endian signed 7.8)
- `SMCFormat.fltToDouble / doubleToFlt` (little-endian IEEE 754; `fltToDouble` returns 0 for non-finite)

Models:
- `FanInfo(id:, actualSpeed:, minimumSpeed:, maximumSpeed:, targetSpeed:, isForced:)`
- `SensorInfo(key:, name:, group:, temperature:)`
- `SensorGroup.title` — Russian display labels (`"CPU Ядра"` / `"E-Cores"` / `"GPU"` / `"Прочие датчики"`)
- `AppState(...)` — CLI/UI snapshot with `isUnlocking`, `updateAvailable`, `readOnlyMode`, scroll bookkeeping <!-- licenseWarning field removed with licensing -->
- `StateSnapshot(fans:, sensors:)` — Codable bundle for XPC `readState`
- `SemanticVersion(string: "X.Y.Z")` (fails on non-3-part input), `SemanticVersion(major:, minor:, patch:)`, Comparable
- `UpdateInfo(currentVersion:, latestVersion:, downloadURL:, releaseNotes:, isNewer:)`

Resources:
- `ResourceReader().readSnapshot() → ResourceSnapshot` — point-in-time raw counters; GPU/disk fields are `nil` when the IORegistry keys are absent on the host
- `ResourceUsageCalculator.reading(prev:, curr:) → ResourceReading` — pure delta computation; the only stateful piece (`prev`) is owned by the caller, not the reader
- `CPUTopologyDetector.detect() → CPUTopology` — hardware-authoritative P/E detection (cache it: topology is static per OS boot)
- `CPUTopology.type(for index: Int) → CPUCoreType` — unknown index → `.performance`
- `ResourceReading.averagePerformanceBusy → Double` / `.averageEfficiencyBusy → Double` — mean `busyPercent` across P / E cores (filtered by `CPUCoreType`); `0` when no cores of that type. Pure computed props (no stored state), tested in `Tests/BlikCoreTests/ResourceModelsTests.swift`
- `ResourceReading.totalDiskBytesPerSec → Double` — sum of `readBytesPerSec + writeBytesPerSec` over all disks
- `CPUTopology.from(entries: [(logicalId, clusterType)]) → CPUTopology` / `CPUTopology.uniform(logicalCount:) → CPUTopology` — pure builders, testable without hardware

<!-- removed: License entry points (LicenseChecker.validate / HardwareID.get / LicenseInfo.status) — entire License/ dir deleted, app is fully free -->

Logging:
- `JSONLogFormatter.format(level:, tag:, message:, payload:) → String` — one-line JSON + `\n`, ISO-8601 ms `ts`, sorted keys
- `JSONLogFormatter.truncateID(_:prefix: 8)` / `maskEmail(_:)` — sanitize helpers

Constants:
- `Constants.appVersion`, `Constants.speedPresets`, `Constants.ftstUnlockDelay`, `Constants.githubOwner`/`githubRepo`, `Constants.updateCheckInterval`, `Constants.updateCheckInitialDelay`, `Constants.minHelperVersionForReadState`, `Constants.minHelperVersionForHistory`, `Constants.pollIntervalOptions`/`defaultPollIntervalSeconds`, history tunables (`historyRawCadenceSeconds`/`historyRawRetention`/`historyRollupRetention`/`historyRawQueryWindow`/`historyDBPath`), terminal/dashboard tunables. <!-- removed: licenseServerURL + all telemetry* + old license constants -->

## Dependencies
- System frameworks: `Foundation`, `IOKit` (AppleSMC service), and system `libsqlite3` (linked via `linkerSettings: [.linkedLibrary("sqlite3")]` for History). <!-- IOPlatformExpertDevice IORegistry access gone with HardwareID; CryptoKit gone with LicenseChecker -->
- External services: none. BlikCore does no network I/O. <!-- licenseServerURL constant removed — server decommissioned, app fully free -->
- No SPM package dependencies (only the system sqlite3 library)

## Side effects
<!-- generated, verify -->
- IOKit: `SMCConnection.init` calls `IOServiceGetMatchingService("AppleSMC")` + `IOServiceOpen` — acquires a kernel `io_connect_t` handle. `deinit` closes it via `IOServiceClose`. Each live `SMCConnection` consumes one kernel handle; daemon holds one per lifetime, CLI/MenuBar each may own one when running with sudo.
- IOKit: every `readKey` / `writeKey` issues a synchronous `IOConnectCallStructMethod`. SMC runs on a serial kernel queue — concurrent calls from multiple threads against the same handle must be externally serialized (the daemon does this via `DispatchQueue` serial).
- IOKit: `writeKey` performs **two** kernel round-trips (a `readKeyInfo` followed by the actual write) on every call — required to populate `dataAttributes`.
- SMC writes (`Ftst`, `F{n}Md`, `F{n}Tg`) mutate **global** hardware state visible to `thermalmonitord` and survive process death until `Ftst=0` is written or the system reboots.
- `SMCWriter.ensureUnlocked` blocks the calling thread for **5 seconds** (`Thread.sleep(forTimeInterval: 5.0)`) after writing `Ftst=1`. Despite `Constants.ftstUnlockDelay = 3.0`, the actual constant used in code is 5s (the 3s value is unused by `SMCWriter`).
- `SMCWriter.setForcedMode(enabled: true)` retries up to 5 times with 2s `Thread.sleep` between attempts → worst case ~8s additional blocking on top of the 5s unlock.
- `SMCWriter.restoreAutoMode` writes `F{n}Md=0` for fans `0..<count` (count defaults to `(modifiedFans.max() ?? 1) + 1`, i.e. **2 fans** for an empty modified set — matches typical MBP).
- `SMCWriter` keeps in-memory `modifiedFans: Set<Int>` and `ftstUnlocked: Bool`. Not thread-safe — a single writer must be owned by a single serialization point.
<!-- removed: LicenseChecker.validate (blocking HTTP + HMAC + hardware serial) and HardwareID.get() (IOPlatformSerialNumber) side effects — License/ dir deleted, app fully free, no network I/O in BlikCore -->
- `JSONLogFormatter` is pure (no I/O, no globals beyond a private `ISO8601DateFormatter`) — safe to call concurrently. The static formatter is thread-safe per Apple docs.

## Invariants / assumptions
<!-- generated, verify -->
- M4 SMC requires the strict ordering **`Ftst=1` → wait 5s → `F{n}Md=1` → `F{n}Tg=RPM`**. Skipping `Ftst` or shortening the wait leaves `F{n}Md` stuck at `3` (system-controlled) and writes to `F{n}Tg` are silently ignored by SMC.
- `SMCConnection.writeKey` MUST call `readKeyInfo()` first to populate `dataType` + `dataAttributes` — without `dataAttributes`, SMC silently discards the write (no kernel error returned). The implementation enforces this internally; callers using raw `callSMC` must replicate the pattern.
- Fan keys use **two different data types** depending on hardware/firmware: legacy `fpe2` (big-endian 14.2 fixed) and modern `flt ` (little-endian IEEE 754). `SMCReader.readFanValue` and `SMCWriter.setFanSpeed` dispatch on the `dataType` returned by SMC — never hardcode either format.
- FPE2 is big-endian (high byte first), SP78 is big-endian signed 7.8, FLT is **little-endian** 32-bit IEEE 754 on Apple Silicon SMC. Mixing endianness corrupts values silently.
- `SMCReader.readFanMode` returns `true` only for `F{n}Md == 1` (user-forced). Both `0` (auto) and `3` (system/thermalmonitord) map to `false`.
- `SMCReader.readTemperature` filters out values `≤ 0` or `≥ 150` °C — sensors not present on the current model return raw garbage; this range gate hides them. Genuinely cold (sub-zero) or extremely hot readings would also be filtered (acceptable trade-off).
- `SMCReader.readAllSensors` probes ~80 keys on every call; absent keys are silently skipped (the underlying `readKey` throws and `readTemperature` returns nil). This is the dominant SMC traffic when polled at 1Hz.
- `SMCFormat.fltToDouble` returns `0` for non-finite floats (NaN/Inf) instead of throwing — downstream code relies on this to avoid propagating NaN into UI.
- `SMCFormat.doubleToFpe2` clamps to `[0, UInt16.max / 4]` — out-of-range RPM silently saturates instead of throwing.
- `ResourceReader` returns **raw counters**, never percentages or rates — usage is meaningless without a previous snapshot. `ResourceUsageCalculator` is the sole place that turns two snapshots into `%`/`By/s`; the daemon stays stateless and the consuming VM owns `prev`.
- `ResourceUsageCalculator` must guard against negative tick/byte deltas (counter wrap or reset after sleep/wake/reconnect) — a negative delta means the prev snapshot is stale, so the sample should be dropped or clamped, not turned into a giant spike.
- CPU core P/E type is determined **authoritatively from hardware**, never from a numbering assumption. `CPUTopologyDetector` reads IODeviceTree `/cpus/*` `cluster-type` + `logical-cpu-id` and maps by id (logical id is NOT guaranteed to follow E-first ordering). The old heuristic "`i < hw.perflevel1.logicalcpu` ⇒ efficiency" is removed — it silently misclassified cores if the kernel ever enumerated P-cores first. Apple Silicon → real per-core map; Intel Mac / no cluster-type → `uniform` (all performance). Unknown index falls back to `.performance` (safe: never hides load in the efficiency group).
- GPU/disk fields in `ResourceSnapshot` are optional by design: hardware/firmware that lacks the `IOAccelerator` PerformanceStatistics or `IOBlockStorageDriver` Statistics keys yields `nil`, and all downstream code (UI sections, History mapping) must tolerate missing series.
- `SemanticVersion(string:)` requires exactly 3 numeric parts. Prerelease/build metadata (`1.2.0-beta+5`) fails to parse — return is `nil`, caller responsibility to handle.
- `SemanticVersion.<` compares major/minor/patch lexicographically as integers; works correctly for `1.10.0 > 1.9.0`.
<!-- removed: LicenseInfo.status reason-string mapping, LicenseChecker HMAC contract, licenseHmacSecret placeholder — License/ dir deleted, app fully free -->
- `Constants.appVersion` and `Constants.minHelperVersionForReadState`/`minHelperVersionForHistory` are rewritten by `scripts/build.sh` before compilation — editing them manually has no effect on shipped PKG.
- All public types use `public` access with explicit `public init` (Swift requirement for cross-module use across SPM targets).
- `smcBytesZero` is the canonical zero 32-byte tuple — never construct the 32-element literal inline (also enforced by code review since the tuple type is opaque).
- `JSONLogFormatter` output is **one JSON object per line**, terminated by `\n` — log readers (helper.log, CLI blik.log) rely on this for line-based parsing.

## Failure hotspots
<!-- generated, verify -->
- **SMC writes silently ignored**: forgetting to populate `dataAttributes` (only happens if `writeKey` is bypassed via direct `callSMC`) or skipping `Ftst=1` unlock. No error surfaces — fan just doesn't change speed. Diagnostic: read back `F{n}Tg` and compare.
- **Stuck forced mode after crash**: if a process dies after `Ftst=1` but before `restoreAutoMode`, fans stay manual until next `Ftst=0` write or reboot. `BlikHelper` mitigates via signal handlers + 5s auto-restore on client disconnect. Symptom: fans pinned to last preset RPM with no client running.
- **`F{n}Md=1` race with thermalmonitord**: on M4 thermalmonitord competes for `F{n}Md` ownership for ~5s after `Ftst=1`. The 5-retry loop with 2s sleep in `setForcedMode` handles this — shortening retries causes intermittent failures (1-2 out of 10 preset switches fail to take).
- **`Constants.ftstUnlockDelay = 3.0` is dead code**: `SMCWriter.ensureUnlocked` hardcodes `Thread.sleep(forTimeInterval: 5.0)`. Anyone tuning the constant expecting effect will be misled — actual knob is in code.
- **FLT endianness regressions**: any new sensor/fan key with `flt ` type must go through `SMCFormat.fltToDouble` (little-endian). Direct byte-pattern reads will produce wildly wrong values that may still pass the 0..150 °C gate.
<!-- removed: License HMAC drift hotspot — LicenseChecker deleted -->
- **`Thread.sleep` on main thread**: `SMCWriter.setForcedMode` / `ensureUnlocked` block the caller for up to ~13s (5s unlock + 5×2s retry). Calling from UI thread freezes the app. All clients must dispatch SMC work to background (daemon already does this on serial queue; direct-SMC CLI/MenuBar run with sudo and have their own background tasks).
<!-- removed: LicenseChecker.validate nil-collapse hotspot — LicenseChecker deleted -->
- **Sensor probe is O(n) reads at startup and per poll**: `readAllSensors` iterates the full `knownSensors` table (~80 entries) per call. Each absent key still costs one `readKeyInfo` + one `readKey` round-trip before failing. At 1Hz this is the dominant SMC traffic.
- **`SMCReader.readFanMode` swallows errors**: any read failure on `F{n}Md` returns `false` (auto), which can make the writer think a forced fan is in auto and re-issue `Ftst=1` unnecessarily.
- **`SMCWriter.restoreAutoMode` defaults to 2 fans** when `modifiedFans` is empty (`fanCount` parameter omitted). On a system with more than 2 fans this leaves trailing fans untouched. Callers that own a real fan count should pass it explicitly.
<!-- removed: IOPlatformSerialNumber-over-HTTP and HardwareID.get() nil hotspots — License/ dir deleted, no network I/O in BlikCore -->

## Related docs
- modules/blik-helper.md — daemon, sole writer in production; owns the only `SMCWriter` instance
- modules/blik-xpc.md — XPC client wrapping the SMC APIs over IPC + `StateSnapshot` Codable transport
- modules/blik-shared.md — VM layer consuming `FanInfo` / `SensorInfo` / `UpdateInfo`
- modules/blik-cli.md — direct-SMC fallback path (sudo) using `SMCReader` + `SMCWriter` without XPC
- modules/blik-menubar.md, modules/blik-app.md — read-only consumers of `FanInfo` / `SensorInfo`
