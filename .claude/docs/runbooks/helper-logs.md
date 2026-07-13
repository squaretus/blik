# Viewing logs across Blik components

One-stop reference for tailing/inspecting logs from CLI (`blik`), MenuBar / GUI apps (`BlikMenuBar`, `BlikApp`), and the privileged daemon (`BlikHelper`). Use this when triaging SMC failures, XPC drops, failed update installs, or license validation errors.

## Steps

### 1. CLI — `blik.log` (file, cwd of invocation)

<!-- generated, verify -->

- Location: `./blik.log` in the directory where `blik` was launched (`Logger.setup(directory: cwd)` in `Sources/blik/Blik.swift` writes to `<cwd>/blik.log`).
- Format: `[yyyy-MM-dd HH:mm:ss.SSS] <message>`, framed by `=== .blik запущен ===` / `=== .blik завершён ===`.
- Tail live:
  ```bash
  tail -f ./blik.log
  ```
- Truncate (file stays open by the running process, so redirect-truncate is the correct idiom):
  ```bash
  > blik.log
  ```
- Implementation: `Sources/blik/App/Logger.swift` — `NSLock`-guarded, `synchronizeFile()` on every write. Single shared file handle.

### 2. MenuBar (`BlikMenuBar`) and GUI (`BlikApp`) — `os.Logger` via unified logging

<!-- generated, verify -->

- Subsystems in use (greppable in `Sources/`):
  - `com.blik.shared` — all VM-слой logging (`AppCoordinator`, `FanControlVM`, `UpdateVM`, `AppSettingsVM`, `BlikRuntime`, `DeviceVM`, plus `Auth/*` and `Telemetry/*`). Categories: `Coordinator`, `FanControl`, `Update`, `Settings`, `Runtime`, `Devices`, `Auth`, `OAuth`, `API`, `Keychain`, `TelemetrySettings`, `TelemetryCoord`, `TelemetrySender`. <!-- `License` category removed: LicenseVM/LicenseChecker заменены на Auth + DeviceVM -->
  - `com.blik.app` — GUI app process (used by `AppLogger`; covers both BlikApp and BlikMenuBar UI per current code).
  - `com.blik.menubar` <!-- not currently used as os.Logger subsystem; only as Mach port name `com.blik.menubar.singleton` -->
- Tail in real time (Console.app or `log` CLI):
  ```bash
  # Shared VM layer (both apps)
  log stream --predicate 'subsystem == "com.blik.shared"' --info

  # MenuBar process specifically
  log stream --predicate 'subsystem == "com.blik.menubar"' --info

  # GUI app
  log stream --predicate 'subsystem == "com.blik.app"' --info

  # Narrow to a category
  log stream --predicate 'subsystem == "com.blik.shared" AND category == "FanControl"' --info
  ```
- Historical (last hour, includes `.info` level):
  ```bash
  log show --predicate 'subsystem BEGINSWITH "com.blik"' --info --last 1h
  ```
- Note: `os.Logger` `.info`/`.debug` messages are NOT persisted by default — use `--info` (and `--debug` if needed) on both `stream` and `show`, otherwise you only see `.default`/`.error`/`.fault`.

### 3. Helper daemon (`BlikHelper`) — file + syslog

<!-- generated, verify -->

Two parallel sinks written by `Sources/BlikHelper/HelperLogger.swift`:

**File** (recommended for post-mortem):
- Path: `/Library/Logs/Blik/helper.log` (uppercase `Blik` in the directory name — see `HelperLogger.swift` constants `logDir`/`logPath`).
- Rotation: when size exceeds 1 MB, current file is renamed to `helper.log.old` (single backup, overwritten on next rotation), new empty `helper.log` is created.
- Tail:
  ```bash
  sudo tail -f /Library/Logs/Blik/helper.log
  ```
- Previous rotation:
  ```bash
  sudo cat /Library/Logs/Blik/helper.log.old
  ```
- Thread safety: `NSLock` + ISO8601 timestamps. Safe to tail while daemon writes.

**syslog / unified logging** (every entry also goes through `NSLog("BlikHelper: %@", message)`):
```bash
log stream --predicate 'process == "BlikHelper"' --info
log show --predicate 'process == "BlikHelper"' --info --last 1h
```

### 4. launchd status — is the daemon actually running?

```bash
# System-domain service (LaunchDaemon)
sudo launchctl print system/com.blik.helper

# Just the load state
sudo launchctl list | grep com.blik.helper
```

Look for:
- `state = running` and a non-zero `pid`.
- `last exit code` — non-zero hints at crash; correlate with `helper.log` timestamps.
- `KeepAlive = true` (configured in `Resources/com.blik.helper.plist`); if daemon flaps, you'll see successive `pid` changes across calls.

The LaunchAgent (per-user GUI/MenuBar autostart) is in the gui domain:
```bash
launchctl print "gui/$(id -u)/com.blik.app"
```

## Common issues — where to look first

### SMC errors (writes ignored, fans stuck, "Разблокировка управления..." hangs)

- **Primary:** `/Library/Logs/Blik/helper.log` — `SMCWriter` log closure routes here. Grep for `Ftst`, `F0Md`, `kIOReturn`, `writeKey`.
- **Sequence to verify** (see `ARCHITECTURE.md` → "Последовательность управления кулером"): `Ftst=1` → 5s sleep → `F{n}Md=1` (up to 5 retries) → `F{n}Tg=RPM`. Missing steps in the log = unlock didn't complete.
- **CLI fallback** (sudo, direct SMC, no daemon): `./blik.log` in the directory `blik` was started from.

### XPC connection failures (CLI prints "helper unavailable", MenuBar shows stale data)

- `helper.log` — connection accept/invalidate lines from `HelperDelegate`.
- `com.blik.shared` / `BlikRuntime` category — client-side XPC errors:
  ```bash
  log stream --predicate 'subsystem == "com.blik.shared" AND category == "Runtime"' --info
  ```
- Check daemon is up: `sudo launchctl print system/com.blik.helper`. If state is not running, look at `last exit code` and tail `helper.log` from the matching timestamp.
- Mach service name mismatch (rare, after rebuild without reinstall): `com.blik.helper` in `XPCConstants.swift`, `MachServices` in `Resources/com.blik.helper.plist`, and `Label` in launchd plist must all match.

### Update check / install failures

- **Check phase** (GitHub Releases API): `helper.log` — `UpdateChecker` logs request URL, HTTP status, parsed `SemanticVersion`.
- **Install phase**: `helper.log` shows download to `/tmp/blik-update.pkg` and `installer -pkg ... -target /` exit status.
- **PKG installer's own logs** (when `installer` invocation succeeds but install fails):
  ```bash
  sudo tail -f /var/log/install.log
  ```
- **Client-side banner state** (UpdateVM): `category == "Update"` in `com.blik.shared`.

### License validation errors <!-- removed: LicenseChecker/LicenseVM/LicenseGateCopy сняты, лицензирование заменено на Auth + DeviceVM -->

- **Auth flow (OAuth + Keychain) and device limits** — relevant categories in `com.blik.shared`:
  ```bash
  log stream --predicate 'subsystem == "com.blik.shared" AND (category == "Auth" OR category == "OAuth" OR category == "API" OR category == "Keychain" OR category == "Devices")' --info
  ```
- **Daemon side**: client authorization decisions live in `Sources/BlikHelper/ClientAuthorization.swift`; rejected/accepted connections are logged via `HelperLogger` in `helper.log` (`rejected connection from pid=...` / `accepted connection pid=...`).

## Where logs / metrics

- CLI: `<cwd>/blik.log`
- Helper daemon (file): `/Library/Logs/Blik/helper.log` (+ `.old` rotation)
- Helper daemon (syslog): `log stream --predicate 'process == "BlikHelper"' --info`
- MenuBar / App / Shared VMs: `log stream --predicate 'subsystem BEGINSWITH "com.blik"' --info`
- PKG installer: `/var/log/install.log`
- launchd state: `sudo launchctl print system/com.blik.helper`

## Related docs

- modules/blik-helper.md
- modules/blik-shared.md
- modules/blik-core.md <!-- was: blik-core-smc.md, файл не существует -->
