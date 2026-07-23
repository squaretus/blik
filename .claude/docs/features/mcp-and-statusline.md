# Claude Code integration: MCP server + statusline

Design spec: `docs/superpowers/specs/2026-07-14-mcp-and-statusline-design.md` (not in git).

## Goal
Let Claude Code read live Mac metrics and drive fan presets. Two CLI subcommands
added to the `blik` executable, both talking to the existing `BlikHelper` daemon
over XPC. No daemon / XPC-protocol / `protocolVersion` changes.

## Scope
- `Sources/blik/App/ClaudeStatuslineCommand.swift` — `claude-statusline` subcommand.
- `Sources/blik/UI/StatuslineRenderer.swift` — pure render + `buildMetrics`.
- `Sources/blik/App/MCPCommand.swift` — `mcp` subcommand + `XPCMetricsSource`.
- `Sources/blik/App/MCPTools.swift` — pure MCP tool layer (`MCPMetricsSource`, `BlikMCPTools`, `CurrentMetricsPayload`).
- `Sources/blik/Blik.swift` — registers `subcommands = [ClaudeStatusline, MCPCommand]`.
- `Package.swift` — new dependency `modelcontextprotocol/swift-sdk`, product `MCP`.

## Changes
- Added: `blik claude-statusline` — metrics for the Claude Code statusLine: avg
  P-core/E-core/GPU temps, RAM used, VRAM used. Color thresholds: temps
  ok<70≤warn<90≤crit; memory by fill ratio 0.7/0.9. Daemon unreachable → empty
  stdout, exit 0 (silent degradation).
- Modified (2026-07-23, `feature/statusline-table`, spec
  `docs/superpowers/specs/2026-07-23-statusline-table-design.md`): the single dense
  line with ▁▂▃▄▅▆▇█ sparklines is replaced by a 5-line box-drawing table
  (`┌─┬─┐` / headers / `├─┼─┤` / values / `└─┴─┘`), columns CPU / E-CORES / GPU /
  RAM / VRAM. Sparklines dropped entirely: `sparkline`, `historyWindow`,
  `sparkPoints`, `StatuslineMetric.spark` and the `queryHistorySync` call are gone —
  the statusline no longer touches history, only `readAllSensorsSync` +
  `readResourcesSync`. Colors unchanged in meaning (frame/headers systemGray,
  values bold + level color, truecolor only).
- Added: `blik mcp` — stdio MCP server. Tools: `get_current_metrics`
  (temps/sensors/CPU% via two `ResourceSnapshot`s 1s apart + RAM/VRAM/fans),
  `list_metrics`, `query_metric_history` (`metric_key` + `minutes`, clamp 1..10080),
  `set_fan_preset` (0/25/50/75/100, 0 = auto; drives physical fans via
  `setFanSpeedPresetSync`).
- Modified: `Blik.swift` root command now has subcommands; no-arg run unchanged (TUI).

## Risks
- `mcp` mode: stdout is the JSON-RPC channel — any stray `print`/stdout logging
  corrupts the protocol. Diagnostics must go to STDERR.
- `get_current_metrics` blocks ~1s (CPU% delta) per call.
- `set_fan_preset` is a real hardware side effect (physical fans), unlike the
  read-only tools.
- Aggregation math must stay in sync with `MetricSampleMapper` group averages.

## How to test
- [ ] Unit: `StatuslineRendererTests` (table layout on plain text via `stripANSI`, centering, equal line widths, truecolor codes, thresholds, degradation), `MCPToolsTests` (dispatch, clamp, preset validation, daemon-down errors) — mock via `MCPMetricsSource`.
- [ ] e2e against installed daemon: use `/usr/local/bin/blik` (NOT `.build/debug/blik` — release daemon strips DEBUG whitelist suffixes → XPC 4097).
- [ ] `blik claude-statusline` with daemon down → empty output, exit 0.
- [ ] `blik mcp` handshake from Claude Code, call each tool, verify no stdout noise.

## Related modules
- modules/blik-cli.md
