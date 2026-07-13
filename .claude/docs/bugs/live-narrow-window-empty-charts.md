# Live charts empty / X-axis collapsed on narrow windows (5/15 min)

## Symptoms
- Charts tab in live mode: after opening the page, a 5-min or 15-min window renders
  almost empty — a couple of minutes of data plus ragged stale fragments from earlier
  page visits. The X-axis "collapses" to the span of available data instead of showing
  the full selected window.
- Wider windows (30 min+) look correct. Classic tell: "30 min is fine, 5/15 are broken".
- Regression noticed in v1.2.0.

## Scope
- `Sources/BlikShared/Charts/ChartsVM.swift` (live-history pull gate + merge).
- `Sources/BlikApp/Views/Charts/ChartFormatting.swift` (`ChartData.segments`, live branch).

## Root cause
Live windows ≤ 15 min were drawn ONLY from the in-memory ring buffer
(`LiveMetricBuffer`, 900 points), which fills only while the page is visible. Daemon
history was pulled exclusively for windows wider than the buffer span:
`restartLiveHistory()` guarded on `liveWindowSeconds > liveBufferSpan` (900 s). So a
freshly opened narrow window had no history, only the thin/stale buffer, and
`MetricChart.window` clamped the left axis edge to the available data.

## Reproduction
1. Live mode, pick a chart, select the 5-min or 15-min window.
2. Open the Charts tab fresh (buffer not yet warm).
3. Observe near-empty chart + X-axis shrunk to a few minutes.
4. Switch to 30 min → full window renders (history was pulled).

## Fix
- `ChartsVM.restartLiveHistory()`: dropped the `liveWindowSeconds > liveBufferSpan`
  gate — daemon history is now pulled for ANY live window (guard kept only on
  `helperSupportsHistory` + `xpcClient != nil`). Property `liveBufferSpan` removed.
- New pure function `ChartsVM.liveMergeSplit(history:bufferSegments:)` splits data into
  "past" (history truncated to the start of the live tail) and "live tail" (last
  contiguous buffer segment). Stale buffer fragments from prior visits are discarded —
  their region is covered by history.
- `ChartData.segments` live branch: buffer-only path remains ONLY when history is
  absent (helper unavailable or not yet loaded); otherwise always merges
  history + tail via `liveMergeSplit`.

## Regression checks
- [ ] Fresh-open 5-min live window shows the full window from daemon history, axis not collapsed.
- [ ] 30-min live window still renders correctly (no double-count / seam at buffer start).
- [ ] Helper without history support (or before first history load) falls back to buffer-only, no crash.
- [ ] Stale buffer fragments from a previous visit do not leak into the plotted series.

## Related files
- `Sources/BlikShared/Charts/ChartsVM.swift`
- `Sources/BlikApp/Views/Charts/ChartFormatting.swift`
- `Tests/BlikSharedTests/ChartLiveMergeTests.swift`
