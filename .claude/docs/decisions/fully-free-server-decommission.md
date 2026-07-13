# ADR — Blik goes fully free; licensing server decommissioned

## Status
Accepted — 2026-07-13.

## Problem
Blik shipped with a server-backed licensing model: OAuth login, per-user
device registration, subscription seats, and an OTLP telemetry pipeline, all
talking to a self-hosted backend at `Constants.licenseServerURL`
(`http://127.0.0.1:3000` in dev). Maintaining that server, its auth stack, and
the telemetry ingest was disproportionate to the product's needs, and the app's
value (SMC fan control + local monitoring) works entirely offline. The decision
was made to make Blik fully free and shut the server down.

## Decision
Make Blik fully free and remove all server-dependent code:

- **Auth / OAuth / subscriptions removed.** Deleted `Sources/BlikShared/Auth/`
  (`AuthVM`, `OAuthClient`, `APIClient`, `KeychainStore`, `AuthNotifications`),
  `DeviceVM`, and all subscription gates (`gatedContent`/`gateBody` in
  Overview / MetricSectionListPage / MenuBarPopupView; `FanDetailView.gateBody`;
  `MenuBarLabel` subscription branch). Deleted `BlikDesign/BlikSubscriptionGate`.
- **Telemetry removed.** Deleted `Sources/BlikShared/Telemetry/` (OTLP builder,
  models, sender, buffer, coordinator, settings, gzip, metric groups).
- **CLI auth removed.** Deleted `Sources/blik/App/{CLIAPIClient,AuthStorage}.swift`
  and the `--token-stdin` / `--logout` / `--device-name` flags + `registerWithPAT`.
- **License primitives removed.** Deleted the whole `Sources/BlikCore/License/`
  dir (incl. `HardwareID`); dropped `Constants.licenseServerURL` and all
  `telemetry*` constants.
- **Coordinator slimmed.** `AppCoordinator` lost `auth`/`devices`/`telemetry`
  props, `needsUpdate`/`minClientVersion`, `checkMinClientVersion()`,
  `observeAuthChanges()`, the auth branch of `handleDeepLink`, and the Keychain
  wipe in `uninstallApp()`. Also removed `AppLogger.swift`.
- **Dependency dropped.** `BlikApp` no longer depends on Kingfisher (avatar UI
  gone); it now has no external package dependencies.
- **Repo hygiene.** Removed root `docs/`, `scripts/import-clickhouse-history.py`,
  `scripts/inject-history-db.sh`, and the telemetry/OAuth test files.

## What stays
- **Auto-update** via GitHub Releases (`squaretus/blik`): `UpdateChecker` /
  `UpdateVM` / `UpdateService` unchanged.
- **Local metric history** (SQLite): `HistoryStore` / `HistoryRecorder` /
  `MetricKey` / `MetricSampleMapper` / `HistoryQuery` unchanged.
- SMC / fans / sensors / resources, XPC, `HelperDelegate`, Charts,
  `MetricNameStore`, design system.
- **Landing page** moved to GitHub Pages (repo `squaretus/blik-landing`);
  releases and the update feed remain on `squaretus/blik`.

## Reasoning
The product is offline-first; the server added operational burden and a privacy
footprint (device serial + telemetry) with little user benefit. Removing it
simplifies the client, eliminates all in-app network I/O except the
GitHub-Releases update check, and lets the project ship as a free tool.

## Consequences
- No login, no accounts, no per-device seats, no usage telemetry. Every feature
  is unconditionally available.
- No client-side network I/O beyond the daemon's GitHub-Releases update check.
- 141 tests remain, all green (removed OAuth/OTLP test suites).
- The security compensations #3 (OAuth state param) and #4 (PKCE in Keychain)
  in `decisions/no-apple-dev-id.md` are now moot — the auth stack they hardened
  no longer exists. That ADR's path-whitelist and root-only-download controls
  still apply.
- The self-hosted `.blik-server` backend is decommissioned; any future paid
  tier would be a fresh decision, not a revert of this one.

## Related
- decisions/no-apple-dev-id.md
- modules/blik-shared.md, modules/blik-app.md, modules/blik-cli.md,
  modules/blik-core.md, modules/blik-design.md, modules/blik-menubar.md
- features/resource-monitoring.md (telemetry-feeding half removed)
