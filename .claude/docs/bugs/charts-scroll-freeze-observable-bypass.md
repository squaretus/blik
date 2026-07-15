# Charts scroll freeze — observable published past the scroll gate

## Symptoms
- Scrolling the «Графики» tab in `BlikApp` stutters / freezes for a beat roughly
  every 4 seconds while live polling is on.
- Only reproduces during live (not range) charts with the daemon feeding history;
  a static tab scrolls smoothly.
- Freeze cadence matches the ~4 s `liveHistoryLoop` period, not the 1 s sample tick.

## Scope
- `BlikShared` `ChartsVM` (live-history publication + scroll gate).
- `BlikApp` `Views/Charts` (`MetricChart` bodies read `charts.liveHistory` via
  `ChartData.segments`).

## Root cause
`ChartsVM.setScrolling` paused **only** the explicit render ticks
(`chartTick` / `summaryTick`). But the 4 s `liveHistoryLoop` → `fetchLiveHistory`
assigned the observable properties `liveHistory` / `rangeBucketSeconds` **directly**,
bypassing the gate. Every visible `MetricChart` body reads `charts.liveHistory`
through `ChartData.segments`, so each 4 s cycle invalidated and fully rebuilt every
on-screen chart (merge + sort + downsample + Swift Charts relayout) mid-scroll.

Compounding it: `@Observable` does **not** deduplicate assignments — writing an
identical payload still fires observers, so even an unchanged live response triggered
a full redraw.

Class of bug: in an `@Observable` architecture it is not enough to gate the
"official" redraw ticks — every write to an observable property that a heavy body
reads must respect the same gate. Sibling to the observation-graph leak in
bugs/menubar-observation-tracking-leak.md.

## Reproduction
1. Install a build with the daemon running (live history available).
2. Open «Графики», keep the tab live (not a fixed range).
3. Scroll continuously and observe a hitch every ~4 s as charts rebuild.

## Fix
`Sources/BlikShared/Charts/ChartsVM.swift`:
- Single publication point `publishLiveHistory(_:bucketSeconds:)`. All live-history
  writes route through it — `fetchLiveHistory` no longer assigns `liveHistory` /
  `rangeBucketSeconds` directly.
- While `scrolling`, it stashes the response in `@ObservationIgnored pendingLiveHistory`
  and returns without mutating observables. `setScrolling(false)` flushes the pending
  payload (then bumps the render ticks once).
- Equal-payload guard: `if dict != liveHistory { … }` / `if bucketSeconds != rangeBucketSeconds { … }`
  so identical responses never touch observers.

`Sources/BlikDesign/Components/BlikPageContainer.swift` (same branch, second bug):
- Horizontal page inset moved from `.padding(.horizontal, …)` on the scroll primitive
  to `.contentMargins(.horizontal, BlikPageMetrics.horizontalPadding, for: .scrollContent)`.
  `.padding` physically narrowed the `List`/`ScrollView`, so the scroll indicator drew
  40 pt inside the window edge; `contentMargins` insets only the content and leaves the
  scrollbar at the window edge. Affects **all** tabs (shared page frame). The doc-comment
  on `BlikPageMetrics.rowInsets` had always claimed the contentMargins approach — the
  implementation had drifted.

## Regression checks
- [ ] Scrolling «Графики» during live polling has no ~4 s hitch.
- [ ] A live response identical to the current one does not re-render charts
      (`withObservationTracking` sees no invalidation on equal payload).
- [ ] A response arriving mid-scroll is deferred and applied on scroll end.
- [ ] Scroll indicator sits at the window edge on every tab, content inset by 40 pt.

## Related files
- `Sources/BlikShared/Charts/ChartsVM.swift` (`publishLiveHistory`, `pendingLiveHistory`, `setScrolling`)
- `Sources/BlikDesign/Components/BlikPageContainer.swift`
- `Sources/BlikApp/Views/Charts/ChartFormatting.swift` (`ChartData.segments`)
- `Tests/BlikSharedTests/ChartsVMTests.swift`
