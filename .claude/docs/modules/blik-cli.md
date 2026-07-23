# blik CLI

## Purpose
Terminal-based fan controller for MacBook Pro (Apple Silicon M4). One executable, two privilege paths:
- `sudo blik` — direct SMC access via IOKit (`SMCDataSource`).
- `blik` (after PKG install) — all SMC operations go through the `BlikHelper` XPC daemon (`XPCDataSource`).
Renders a four-column ANSI dashboard in raw-mode terminal, polls fans/sensors on a configurable interval, applies one of five speed presets via number keys. Also serves as a CLI surface for non-TUI sub-flows: `--diagnose` (SMC key dump), `--update` (force-update via daemon). Two `ArgumentParser` subcommands integrate the CLI with **Claude Code**: `claude-statusline` (an ANSI table of aggregated metrics for the Claude Code statusLine) and `mcp` (a stdio MCP server exposing metrics/fan-control tools). The app is fully free: the former auth flags (`--token-stdin`, `--logout`, `--device-name`) and the `AuthStorage` / `CLIAPIClient` device-registration stack were **removed** when the licensing server was decommissioned (2026-07-13). The CLI now does no network I/O of its own — the only remote interaction is `--update`, routed through the daemon to GitHub Releases.

## Key files
- `Sources/blik/Blik.swift` — `@main`, `ParsableCommand`. Single `run()` dispatches all sub-flows (update / XPC-TUI / direct-SMC TUI / diagnose / once). `configuration.subcommands = [ClaudeStatusline, MCPCommand]`; no-argument invocation still runs the TUI. <!-- logout / token-stdin flows removed -->)
- `Sources/blik/App/ClaudeStatuslineCommand.swift` — `ClaudeStatusline` subcommand (`claude-statusline`). Wires XPC data (sensors + `readResourcesSync` snapshot) into `StatuslineRenderer`, prints the table. No history reads. Daemon unreachable → empty stdout, exit 0.
- `Sources/blik/UI/StatuslineRenderer.swift` — pure render layer: `buildMetrics` (aggregates P-core/E-core/GPU temps like `MetricSampleMapper`, RAM/VRAM used) + `render` (5-line box-drawing table, columns CPU / E-CORES / GPU / RAM / VRAM). Column width = `max(header, value) + 2`, content centered (odd remainder goes right), widths computed on plain text so ANSI never shifts the frame. No I/O; missing sources are silently skipped.
- `Sources/blik/App/MCPTools.swift` — pure MCP layer: `MCPMetricsSource` protocol (the XPC boundary, mocked in tests), `CurrentMetricsPayload` (Codable, `build(sensors:fans:reading:)`), `BlikMCPTools` (tool definitions + `handle` dispatcher). No XPC, no `print`.
- `Sources/blik/App/MCPCommand.swift` — `MCPCommand` subcommand (`mcp`) + `XPCMetricsSource` (real `MCPMetricsSource`, lazy reconnect to daemon). Runs the swift-sdk `Server` over `StdioTransport` inside `Task` + `dispatchMain()`, `waitUntilCompleted`, `exit(0)` when stdin closes.
- `Sources/blik/App/FanController.swift` — TUI loop (`poll → render → key → sleep`). Owns the `AppState`.
- `Sources/blik/App/FanDataSource.swift` — protocol abstracting SMC vs XPC.
- `Sources/blik/App/SMCDataSource.swift` — direct IOKit path. Owns `SMCReader`/`SMCWriter`, calls `restoreAutoMode` on startup.
- `Sources/blik/App/XPCDataSource.swift` — daemon path. Wraps `BlikXPCClient` sync API, picks up `updateAvailable` on startup.
- `Sources/blik/App/SignalHandler.swift` — async-signal-safe SIGINT/SIGTERM handler (single volatile flag).
- `Sources/blik/App/Logger.swift` — thread-safe file logger (`blik.log` in CWD) guarded by `NSLock`.
- `Sources/blik/App/Diagnostics.swift` — `--diagnose` SMC key dumper (iterates `kSMCGetKeyFromIndex` over `#KEY` count).
<!-- removed: AuthStorage.swift (~/.config/blik/auth.json PAT store) and CLIAPIClient.swift (sync HTTP to licensing server) — deleted, app fully free -->
- `Sources/blik/UI/Terminal.swift` — termios raw mode, alt-screen, cursor, mouse-reporting disable, synchronized-update (`?2026h/l`).
- `Sources/blik/UI/ANSIRenderer.swift` — colors, progress bars, temperature/fan-speed color gradients, box-drawing constants.
- `Sources/blik/UI/KeyboardInput.swift` — non-blocking `read()` from STDIN, ESC-sequence parser.
- `Sources/blik/UI/DashboardView.swift` — four-column tile layout renderer (Fan column + CPU/E-Core/GPU + control bar).

## Entry points
- `Blik.run()` — `ArgumentParser` entrypoint. Flags: `--read-only`, `--once`, `--interval <Double>` (default 1.0), `--diagnose`, `--update`. Dispatch order in `run()`: update → XPC-TUI (non-root + helper reachable) → root error → direct-SMC TUI/once/diagnose. <!-- removed: --token-stdin / --logout / --device-name flags and their dispatch steps — auth stack deleted -->
- `FanController.run()` — TUI main loop, shared by both data sources.
- `Diagnostics.run(connection:)` — one-shot SMC key dump (`F*` and `T*` keys with decoded values).
- `SignalHandler.install()` — installs SIGINT/SIGTERM handlers (sets `shouldTerminate` only).
- `KeyEvent` cases — `up`, `down`, `pageUp`, `pageDown`, `preset(Int)` (0/25/50/75/100), `quit`, `none`.
- `ClaudeStatusline.run()` — one-shot statusline. `MCPCommand.run()` — long-lived stdio MCP server.
- `StatuslineRenderer.buildMetrics(sensors:snapshot:) → [StatuslineMetric]`, `.render([StatuslineMetric]) → String` (5-line box-drawing table). Thresholds: temps ok<70≤warn<90≤crit; memory by fill ratio 0.7/0.9.
- `BlikMCPTools.toolList` / `.handle(name:arguments:source:) → CallTool.Result`. Tools: `get_current_metrics`, `list_metrics`, `query_metric_history` (`metric_key` + `minutes`, clamped 1..10080), `set_fan_preset` (`percent` ∈ {0,25,50,75,100}, 0 = auto).
- `CurrentMetricsPayload.build(sensors:fans:reading:)` — pure aggregation from domain models (same group-average math as `MetricSampleMapper`/Overview).
<!-- removed: AuthStorage.{load,save,delete} and CLIAPIClient.{registerDevice,listDevices} entry points — files deleted -->

## Dependencies
- `BlikCore` — `SMCConnection`, `SMCReader`, `SMCWriter`, `FanInfo`, `SensorInfo`, `AppState`, `SensorGroup`, `Constants`, `SMCParamStruct`, `SMCSelector`, `SMCFormat`, `SMCBytes`. <!-- removed: HardwareID (License/ dir deleted), LicenseStatus (unused) -->
- `BlikXPC` — `BlikXPCClient` (sync wrappers: `readAllSensorsSync`, `readAllFansSync`, `readResourcesSync`, `queryHistorySync`, `listHistoryMetricsSync`, `setFanSpeedPresetSync`), `UpdateService` (used only on `--update`). `HistoryQueryRequest`/`HistoryQueryResponse`, `MetricKey` from `BlikCore`. `ResourceUsageCalculator.reading(from:to:)` for CPU% delta.
- External package: `apple/swift-argument-parser` (≥ 1.3.0), `modelcontextprotocol/swift-sdk` (product `MCP`, imported only by `MCPTools.swift`/`MCPCommand.swift`).
- System: `IOKit` (only with `SMCDataSource`), `Foundation` (`FileManager` for logging), `Darwin` (`termios`, `signal`, `ioctl`, `read`, `geteuid`). <!-- URLSession no longer used — no HTTP in CLI -->
- Network: none. <!-- removed: licensing server at licenseServerURL — --token-stdin flow deleted -->

## Side effects
<!-- generated, verify -->
- **Filesystem:**
  - `blik.log` created/truncated in `FileManager.default.currentDirectoryPath` (NOT user home) on TUI startup via `Logger.setup`. `synchronizeFile()` after every line. Closed in `FanController.cleanup`.
  <!-- removed: ~/.config/blik/auth.json write + directory creation — AuthStorage deleted -->
- **Terminal STDIN:** `tcsetattr(STDIN_FILENO, TCSAFLUSH)` to disable `ICANON|ECHO|ISIG` (so `Ctrl-C` becomes a byte, not a signal), set `VMIN=0/VTIME=1`. Reversed via stashed original `termios` in `Terminal.disableRawMode` and `Terminal.deinit`.
- **Terminal STDOUT:**
  - Alt-screen enter/leave (`ESC[?1049h/l`), cursor hide/show (`ESC[?25l/h`), all-mode mouse-reporting disable (`?1000/1002/1003/1006l`), synchronized update bracketing (`?2026h/l`) around every render to avoid tearing.
  - Continuous ANSI sequences during TUI. `fflush(stdout)` after every `Terminal.write`.
- **STDERR:** Used for permission-error warnings (`FileHandle.standardError.write`) before `ExitCode(...)` throws. <!-- license/HTTP-error warnings gone with auth stack -->
- **SMC writes (direct path only):** via `SMCWriter` — `Ftst`, `F{n}Md`, `F{n}Tg`. `SMCDataSource.onStartup` unconditionally calls `writer.restoreAutoMode(fanCount:)` (clears orphaned manual state from a prior crashed run). `FanController.cleanup → dataSource.restoreAutoMode` on exit.
- **XPC (daemon path):**
  - Connects to `com.blik.helper` mach service via `BlikXPCClient.connectAndVerify()`.
  - Calls: `readAllFansSync`, `readAllSensorsSync`, `setFanSpeedPresetSync`, `restoreAutoModeSync`, `checkForUpdateSync` (on startup), and `UpdateService.checkAndInstall` (on `--update`). <!-- removed: getLicenseStatusSync, validateLicenseSync — no license enforcement -->
  - Disconnects only inside `XPCDataSource.restoreAutoMode` (called from `cleanup`). Other flows leak the connection until process exit.
<!-- removed: Network (HTTP) — the --token-stdin device-registration POST is gone; CLI does no HTTP -->
- **Process signals:** `signal(SIGINT, ...)` and `signal(SIGTERM, ...)` installed via `SignalHandler.install()`. Not restored on exit.
- **No SwiftUI / no Cocoa main loop.** Pure run loop in `FanController.run()` driven by `usleep(Constants.pollIntervalMicroseconds)`.
- **`claude-statusline`:** single `print()` of a multi-line table to stdout (or nothing if daemon unreachable / no metrics), then exit 0. Read-only XPC calls, disconnects via `defer`.
- **`mcp` server:** stdout is the MCP protocol channel — `print` is forbidden in this mode (all diagnostics go to STDERR via `FileHandle.standardError`). `get_current_metrics` performs `Thread.sleep(forTimeInterval: 1.0)` between two `readResourcesSync` snapshots to derive CPU%, so that tool call blocks ~1s. `set_fan_preset` drives **physical fans** through the daemon (`setFanSpeedPresetSync`) — a real side effect on hardware, unlike every other tool which is read-only.

## Invariants / assumptions
<!-- generated, verify -->
- **Privilege gate:** TUI without `--read-only`/`--once`/`--diagnose` requires either `geteuid() == 0` or a reachable `BlikHelper`. Read-only paths and `--once` go through direct SMC (read can work without root in practice, but the binary still calls `SMCConnection()` unconditionally — see hotspots).
- **No license enforcement anywhere.** The app is fully free — there is no license/subscription/auth gate in the CLI or in any other surface. Both `sudo blik` (direct SMC) and `blik` (XPC) start the TUI unconditionally.
- **Flag precedence in `run()`:** `--update` > TUI/once/diagnose. <!-- former --logout / --token-stdin precedence steps removed with the auth flags -->

- **SignalHandler contract:** `shouldTerminate` is `nonisolated(unsafe)` and is the **only** state the handler touches. Main loop polls it every iteration before `KeyboardInput.readKey`. Cleanup happens on the main thread via the deferred `cleanup()` in `FanController.run()`.
- **Logger contract:** Thread-safe via single `NSLock`. `writeUnsafe` must only be called while the lock is held. `Logger.log` before `setup` silently no-ops (guarded by `fileHandle != nil`). `setup` truncates the existing file (`createFile(...)`).
- **`FanController.applyPreset` ordering:** UI state (`fans[i].isForced`, `targetSpeed`, `currentPreset`) is mutated **before** calling `dataSource.applyPreset`, but the writer receives the *original* `state.fans` snapshot, so `SMCWriter.setAllFansSpeed`'s `isForced` check sees the pre-mutation state. Critical for first-switch behavior: writer must see `isForced == false` to perform the full unlock sequence (`Ftst=1` → sleep 5s → `F{n}Md=1`).
- **Poll vs. tick:** `--interval` (default 1.0s, Double) is the SMC/XPC poll cadence. `Constants.pollIntervalMicroseconds` is the inner `usleep` between keyboard reads — keyboard responsiveness, not data rate.
- **Flood guard:** `KeyboardInput.readKey` returns `.none` if `read()` returned more than `Constants.inputFloodThreshold` bytes — protects against paste-flood / mouse-report flood that would otherwise spam preset switches.
- **Hotkeys:** `1`/`2`/`3`/`4`/`5` → presets `0`/`25`/`50`/`75`/`100`. `↑`/`↓` and PageUp/PageDown scroll the "Остальные сенсоры" tile. `q`/`Q` quits. `ESC O <X>` style sequences (DEC private mode) are **not** parsed — only `ESC [ <X>`.
- **Auto-restore on exit:** Both `SMCDataSource.restoreAutoMode` (via `writer.restoreAutoMode`) and `XPCDataSource.restoreAutoMode` (via `BlikXPCClient.restoreAutoModeSync` + `disconnect`) are called from `FanController.cleanup()`. The XPC path **also** triggers daemon's `auto-restore on disconnect` 5s timer as a fallback.
- **`SMCDataSource.mergeFanData` smart merge:** for fans the writer is currently driving (`writer.modifiedFanIds.contains(i)`), it preserves local `targetSpeed`/`isForced` and calls `reinforceSpeed` directly instead of overwriting from SMC. For other fans, it accepts the fresh SMC values. `XPCDataSource.mergeFanData` uses a simpler rule: trust local values whenever `currentPreset != 0` (daemon's reinforce timer drives the actual fans).

## Failure hotspots
<!-- generated, verify -->
- **Terminal not restored on `SIGKILL`.** Alt-screen / raw-mode / hidden-cursor survive an uncatchable kill. `Terminal.deinit` covers Swift normal exits but not `_exit`/`SIGKILL`. Recovery: shell `reset` or close the tab. `ISIG` is disabled in raw mode → `Ctrl-C` is delivered as a byte, **not** as SIGINT. SIGINT/SIGTERM only arrive from external `kill`.
- **`SMCConnection()` called unconditionally on non-XPC paths.** Even with `--read-only` or `--once`, the binary opens an IOKit session. On macOS where the SMC service is restricted, this may fail before reaching the read path. Worth checking if read-only is supposed to work as a regular user.
- **`SMCDataSource.onStartup` always wipes all fans to auto.** If a second `blik` instance starts while another is running, it stomps the running instance's manual state. There is no IPC/lockfile between CLI instances.
- **`XPCDataSource.restoreAutoMode` ignores `restoreAutoModeSync()`'s `Bool` return.** Failure during shutdown is silently swallowed. If the daemon is dead at exit, fans remain in manual until the daemon's own auto-restore-on-disconnect timer fires (~5s after all XPC clients drop).
- **`Diagnostics.run` is O(`#KEY`) with no progress UI.** On a healthy SMC `#KEY` is several hundred; the scan iterates all of them with two SMC calls each (`kSMCGetKeyFromIndex` + `readKey`). Noticeable pause, no spinner.
- **`KeyboardInput.readKey` parses only `ESC [` sequences.** Terminals that emit DEC private (`ESC O A`) for arrow keys won't scroll the "Остальные" tile. Modern terminals (iTerm2, Apple Terminal) are fine.
<!-- removed: HTTP-path hotspot — CLIAPIClient / --token-stdin deleted, CLI does no HTTP -->
- **`Update` path is fire-and-forget.** `UpdateService.checkAndInstall` returns once the daemon kicks `installer -pkg`; the daemon will then `bootout`/`bootstrap` itself, and the running `blik`'s XPC channel goes dead. Subsequent calls in the same process won't reconnect.
- **`Logger.setup` truncates `blik.log` on each TUI start.** History is lost. Tail/diff-based workflows need to capture logs externally.
- **`Logger` writes to CWD, not `~/Library/Logs` or `/tmp`.** Running `blik` from a read-only or world-writable directory has undefined log-file behavior (silent no-op or permission error).
- **Debug CLI is NOT authorized by a release daemon (XPC error 4097).** The PKG release build of `BlikHelper` strips `#if DEBUG` debug-suffix entries from the `ClientAuthorization` whitelist, so a locally built `.build/debug/blik` cannot connect to the *installed* release daemon. For any e2e check of `blik mcp` / `blik claude-statusline` against the installed daemon, use the installed binary at `/usr/local/bin/blik`, not `.build/debug/blik`.
- **`get_current_metrics` blocks ~1s per call** (two-snapshot CPU% delta). Fine for an on-demand MCP tool, but a client polling it in a tight loop will serialize on that sleep.
- **`mcp` accidental stdout writes corrupt the protocol.** Any stray `print`/logging to stdout from a dependency mixes into the JSON-RPC stream and breaks the Claude Code MCP client. Keep all diagnostics on STDERR.
- **`AppState.fans.count` mismatch:** `XPCDataSource.mergeFanData` handles count change (`currentFans = newFans`), but `SMCDataSource.mergeFanData` only updates indices that exist in both arrays — if the fan count somehow shrinks, stale entries persist in `state.fans`.

## Related docs
- `modules/blik-core.md` — SMC reader/writer, formats, `Constants`.
- `modules/blik-xpc.md` — `BlikXPCClient` sync API and `UpdateService`.
- `modules/blik-helper.md` — daemon target of `--update` and the regular XPC TUI path.
- `decisions/fully-free-server-decommission.md` — app went fully free, server decommissioned.
- `features/mcp-and-statusline.md` — Claude Code integration (`mcp` server + `claude-statusline`).
