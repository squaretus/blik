# Release version stamped into XPC protocol version broke capability gates

## Symptoms
Observed on public releases 1.0.0 / 1.1.0 (dev numbering was already 2.x, public
releases restarted at 1.0.0):
- Charts «История недоступна: хелпер не установлен или устарел» banner, empty graphs —
  even though the daemon was actively writing history to the SQLite DB.
- Sluggish live polling — noticeable extra latency per refresh tick.
- Settings still showed «Helper: Установлен» (status only probes the XPC connection,
  not the capability gates), so the "helper missing" banner looked contradictory.

## Scope
- `Sources/BlikXPC/XPCConstants.swift` (`helperVersion` stamp)
- `Sources/BlikCore/Constants.swift` (`minHelperVersionForReadState`, `minHelperVersionForHistory`)
- `scripts/build.sh` (version substitution)
- Consumers: `BlikRuntime.helperSupportsHistory`, `FanControlVM.refreshData()`.

## Root cause
`scripts/build.sh` ran a `sed` that substituted the **release** version into
`BlikXPCConstants.helperVersion` (same treatment as `Constants.appVersion`). The
client capability gates compare against that same constant:
- `Constants.minHelperVersionForReadState = "1.3.1"`
- `Constants.minHelperVersionForHistory = "2.11.0"`

When the public release version (1.0.0 / 1.1.0) was stamped in, the freshly built
helper reported `helperVersion` = 1.x — **below its own history gate (2.11.0)**. So
the client concluded the just-installed helper was too old for history (empty-state
banner) and too old for `readState`, falling back to the legacy path.

Two distinct downstream effects:
1. **History unavailable.** `helperSupportsHistory` = false → charts range mode
   short-circuits to empty-state, hiding data the daemon was really recording.
2. **Live-polling lag.** Without `supportsReadState`, `FanControlVM.refreshData()`
   takes the legacy path with two sequential XPC round-trips (`readAllFans` →
   `readAllSensors`) instead of the single combined `readState`.

The gate constants themselves are correct; the bug was feeding them a version number
that meant "marketing release" instead of "XPC protocol capability level".

## Reproduction
1. Set dev protocol numbering to 2.x with gates at 1.3.1 / 2.11.0.
2. Build a release with a marketing version below the history gate (e.g. `1.1.0`).
3. Install; open Charts range mode → empty-state «хелпер устарел» despite a recording
   daemon; observe extra latency on the live tab (double round-trip).

## Fix
- Renamed `XPCConstants.helperVersion` → `protocolVersion`: an XPC-protocol capability
  level, decoupled from the release version, bumped manually only when the XPC surface
  changes. `build.sh` no longer `sed`s this file (the substitution line was removed).
- `minHelperVersionFor*` gates are documented/compared against `protocolVersion` and
  must never be raised above the current `protocolVersion`.
- `getHelperVersion` now replies `BlikXPCConstants.protocolVersion`.
- New `Tests/BlikXPCTests/XPCProtocolVersionTests.swift` locks the invariants:
  `protocolVersion` is valid semver; a fresh helper satisfies both gates
  (`protocolVersion >= minHelperVersionForReadState` and `>= minHelperVersionForHistory`);
  `build.sh` contains no `sed` touching `XPCConstants.swift`.

## Regression checks
- [ ] Build a release with marketing version below the history gate → fresh helper
      still passes both capability gates (protocolVersion unchanged by build.sh).
- [ ] Charts range mode shows data (not empty-state) on a freshly installed helper.
- [ ] Live tab uses the single `readState` round-trip, not `readAllFans` + `readAllSensors`.
- [ ] `XPCProtocolVersionTests` green.

## Related files
- `Sources/BlikXPC/XPCConstants.swift`
- `Sources/BlikCore/Constants.swift`
- `Sources/BlikHelper/HelperDelegate.swift`
- `scripts/build.sh`
- `Tests/BlikXPCTests/XPCProtocolVersionTests.swift`
