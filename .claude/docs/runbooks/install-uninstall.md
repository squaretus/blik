# Install / Uninstall

End-to-end install via PKG wizard and three full-cleanup uninstall paths (all converge on the same set of artefacts).

## Install

### Artefacts dropped by PKG

- `/Applications/Blik.app` — GUI + MenuBar app bundle
- `/Library/PrivilegedHelperTools/com.blik.helper` — daemon binary (root)
- `/Library/LaunchDaemons/com.blik.helper.plist` — daemon autoload
- `/Library/LaunchAgents/com.blik.app.plist` — agent autoload (user session)
- `/usr/local/bin/blik` — CLI in `PATH`

### Steps

1. Build PKG: `scripts/build.sh <VERSION>` → `.build/release_build/Blik-<VERSION>.pkg`.
2. Open PKG, walk through wizard (welcome.html → conclusion.html).
3. `scripts/preinstall` runs first (only meaningful on upgrade): `killall BlikMenuBar`, `launchctl bootout gui/<uid>/com.blik.app`, `launchctl bootout system/com.blik.helper`. Always exits 0.
4. PKG copies bundles + plists + CLI to the destinations above.
5. `scripts/postinstall`:
   - `chown root:wheel` + `chmod` on helper binary (`755`), daemon plist (`644`), agent plist (`644`).
   - `launchctl bootstrap system /Library/LaunchDaemons/com.blik.helper.plist` — daemon starts as root.
   - Resolves console user via `stat -f '%Su' /dev/console` (avoids `$USER=root` when invoked from daemon during in-app update).
   - `launchctl bootstrap gui/<console_uid> /Library/LaunchAgents/com.blik.app.plist`.
   - Fallback: if `pgrep -x BlikMenuBar` shows no process after 1s, `sudo -u <console_user> open /Applications/Blik.app`.
   - `mkdir -p /usr/local/bin` (just in case).

### Verifying install

- `launchctl print system/com.blik.helper` — daemon running.
- `launchctl print gui/<uid>/com.blik.app` — agent loaded.
- `pgrep -x BlikMenuBar` — MenuBar app process visible.
- `tail -f /Library/Logs/Blik/helper.log` — daemon log; first line `initialized, SMC connection established (appExisted=1)`.

## Uninstall — three entry points, one outcome

All three paths must wipe the **same** set of paths. If you add a new artefact to install, add it to **all three** cleanup paths (Swift `performUninstall` + `cleanupUserData`, `uninstall-helper.sh`). Drift here is the failure mode that leaves orphan plists or TCC entries.

### Path 1 — BlikApp DangerCard button (preferred)

1. User opens BlikApp → Settings → "Удалить .blik" → confirmation dialog.
2. `FanControlVM.uninstallApp()` calls `helper.uninstallAll` via XPC.
3. If XPC client is unavailable (helper not reachable) → falls back to `uninstallViaScript()` which extracts `uninstall-helper.sh` from the app bundle to `/tmp/`, then runs it via `osascript ... with administrator privileges`. The fallback waits for `osascript` to exit (`process.waitUntilExit()` on a detached Task) before flipping `shouldTerminate`.
4. After 6s the VM sets `shouldTerminate = true` to close the app even if daemon shutdown lags.

`HelperDelegate.uninstallAll`:
- Runs on `smcQueue`.
- `writer.restoreAutoMode()` first (fans back to auto before files vanish).
- Replies to client `before` deletion to avoid XPC connection drop, then sleeps 0.5s.
- Calls `performUninstall(removeApp: true)`.

### Path 2 — Drag Blik.app to Trash (Finder)

1. User drags `/Applications/Blik.app` to Trash.
2. Daemon's `reinforceTimer` (1s tick) checks `FileManager.fileExists(atPath: "/Applications/Blik.app")`.
3. Guard: `appExistedOnStart == true` AND `activeConnections == 0` AND app file missing — only then self-uninstall fires (prevents triggering during PKG upgrade when app is briefly absent).
4. `writer.restoreAutoMode()` then `performUninstall(removeApp: false)` (app already gone, don't try to remove again).

Log line on trigger: `app удалён из Finder, выполняю самоочистку`.

### Path 3 — Terminal script

```bash
cp /Applications/Blik.app/Contents/Resources/uninstall-helper.sh /tmp/
bash /tmp/uninstall-helper.sh
```

Used when daemon is dead or unreachable. Same artefact list, executed entirely from shell with `sudo`.

## What gets cleaned (single source of truth)

| Artefact | Swift `performUninstall` | `uninstall-helper.sh` |
|---|---|---|
| `/usr/local/bin/blik` | yes | yes |
| `/Library/LaunchAgents/com.blik.app.plist` | yes | yes |
| `/Library/LaunchDaemons/com.blik.helper.plist` | yes | yes |
| `/Library/PrivilegedHelperTools/com.blik.helper` | yes (self) | yes |
| `/Applications/Blik.app` | only if `removeApp=true` | yes |
| `~/Library/Logs/blik/` (all users in Swift, current in script) | yes | yes |
| `~/Library/Preferences/com.blik.*` | yes | yes |
| `~/Library/Caches/com.blik.*` | yes | yes |
| TCC reset `com.blik.app` | `tccutil reset All com.blik.app` | same |
| PKG receipt `com.blik.pkg` | `pkgutil --forget` | same |
| LaunchAgent bootout `gui/<uid>/com.blik.app` | iterates `/Users/*` by owner UID (`.ownerAccountID`) | uses `id -u $USER` |
| LaunchDaemon bootout `system/com.blik.helper` | last step (kills self) | yes |

Notes:
- Daemon path enumerates `/Users` and reads each home directory's owner UID (`FileManager.attributesOfItem` → `.ownerAccountID`) to call `launchctl bootout gui/<uid>/com.blik.app`. Earlier hardcode `501...510` was removed because it missed custom UIDs and migrated accounts.
- Daemon deletes its own binary **before** `launchctl bootout system/...` so launchd can't respawn it; bootout is the last action and terminates the process.
- Reply over XPC happens **before** file deletion (`uninstallAll`) — otherwise client sees connection drop and treats it as failure.

## Common issues

- **Daemon refuses to start after PKG install** — check plist permissions (`launchctl bootstrap` is strict about ownership). `postinstall` does `chown root:wheel` + `chmod 644`; if you edit the plist by hand and lose root ownership, bootstrap fails silently. Fix: `sudo chown root:wheel /Library/LaunchDaemons/com.blik.helper.plist && sudo launchctl bootstrap system /Library/LaunchDaemons/com.blik.helper.plist`.
- **MenuBar app didn't launch after install** — `postinstall` fallback uses `sudo -u <console_user> open` if `pgrep -x BlikMenuBar` is empty after 1s. If both bootstrap and open failed, console user resolution probably returned empty (e.g., installer run via SSH without console session). Manual: `open /Applications/Blik.app`.
- **Uninstall via DangerCard hangs** — daemon unreachable. VM falls back to `uninstallViaScript` after XPC failure path, but if helper is mid-deadlock, fallback won't trigger. Workaround: terminal Path 3.
- **Finder self-uninstall didn't fire** — daemon only triggers when `activeConnections == 0`. If BlikMenuBar/BlikApp/CLI is still connected, daemon waits. Quit all clients, wait 1–2s for `reinforceTimer` to notice.
- **TCC permissions linger after uninstall** — `tccutil reset All com.blik.app` clears app bundle's TCC entries but not those issued to the helper. Helper has no UI prompts so this is usually a non-issue; if it becomes one, add `tccutil reset All com.blik.helper`.

## Where logs / metrics

- Daemon: `/Library/Logs/Blik/helper.log` (rotates at 1 MB → `helper.log.old`).
- Daemon syslog: `log stream --predicate 'process == "BlikHelper"' --info`.
- Install/uninstall syslog: `log show --predicate 'process == "installer"' --last 10m`.
- launchd state: `launchctl print system/com.blik.helper`, `launchctl print gui/<uid>/com.blik.app`.

## Related docs

- modules/blik-helper.md (daemon internals, smcQueue, reinforceTimer)
- modules/build-pipeline.md <!-- removed --> (scripts/build.sh, VERSION injection)
