# Debugging SMC fan control on M4

Procedure for diagnosing SMC fan-control failures on Apple Silicon M4 (no RPM change after preset, write silently ignored, unexpected auto-restore).

## Steps

1. **Dump SMC keys via diagnose mode.**
   ```
   sudo .build/debug/blik --diagnose
   ```
   Iterates over all SMC keys via `kSMCGetKeyFromIndex` and prints every `F*` and `T*` key with type, size, raw bytes and decoded value. Key fields to inspect:
   - `Ftst` (ui8) — unlock flag. `0` = thermalmonitord controls fans, `1` = user-controlled.
   - `F{n}Md` (ui8) — fan mode. `0` = auto, `1` = forced (user), `3` = system (thermalmonitord).
   - `F{n}Tg` (fpe2 or flt) — target RPM (what we write).
   - `F{n}Ac` (fpe2 or flt) — actual RPM (what fan reports back).
   - `F{n}Mn` / `F{n}Mx` — min/max RPM bounds. Used to compute preset RPM as `min + (max - min) * pct / 100`.
   - `FNum` (ui8) — fan count.
   Implementation: `Sources/blik/App/Diagnostics.swift`.

2. **Verify M4 unlock sequence happened.**
   On M4, writes to `F{n}Tg` are silently ignored until `Ftst=1` is written and thermalmonitord releases `F{n}Md` (3→0). Confirm the full sequence:
   ```
   1. Ftst = 1                    (one-time unlock, ui8)
   2. Thread.sleep(5.0)           (mandatory wait — thermalmonitord lag)
   3. F{n}Md = 1                  (forced mode, retry up to 5x with 2s gap)
   4. F{n}Tg = RPM                (fpe2 little-endian-pair or flt little-endian)
   5. reinforceSpeed() every 1s   (daemon re-writes F{n}Tg to keep value sticky)
   ```
   If `--diagnose` shows `Ftst=0` while the app claims it set a preset, the unlock write failed (likely permissions — need root). If `F{n}Md=3` after the 5s wait, thermalmonitord did not release control — see step 6.
   Implementation: `SMCWriter.ensureUnlocked()` + `SMCWriter.setForcedMode()` in `Sources/BlikCore/SMC/SMCWriter.swift`.

3. **Confirm `writeKey()` fetched `dataAttributes`.**
   `SMCConnection.writeKey()` **must** call `readKeyInfo(key:)` first to populate `input.keyInfo.dataAttributes` from current key metadata. Without it, the kernel SMC interface accepts the call (`IOConnectCallStructMethod` returns success) but silently discards the write — no error surfaces. If you see `kIOReturnSuccess` on every write but values do not change, that's the symptom. Source: `Sources/BlikCore/SMC/SMCConnection.swift` lines 82–100.

4. **Check data-format encoding.**
   - **FPE2** (RPM): 14 integer + 2 fractional bits, big-endian byte pair. `raw = value * 4`, byte0 = high, byte1 = low. Used for `F{n}Ac`/`F{n}Tg`/`F{n}Mn`/`F{n}Mx` on older keys.
   - **SP78** (temperature): signed 7.8 fixed-point, big-endian byte pair. `value = Int16 / 256`. Used for `T*` keys with `sp78` type.
   - **FLT** (32-bit IEEE 754 float, **little-endian** on Apple Silicon): byte0 = LSB, byte3 = MSB. Apple Silicon SMC reports many F* and T* keys as `flt ` — Intel-era code that assumes big-endian floats will produce garbage values (NaN, huge numbers, near-zero). Detection: read key, branch on `dataType == fourCharCode("flt ")`.
   Implementation: `SMCFormat` in `Sources/BlikCore/SMC/SMCTypes.swift` lines 6–54.

5. **Inspect helper daemon log.**
   ```
   cat /Library/Logs/Blik/helper.log
   ```
   Look for lines like:
   - `SMCWriter: Ftst=1 (unlock)` — unlock attempted.
   - `SMCWriter: waited 5s for mode transition` — passed the mandatory wait.
   - `SMCWriter: F{n}Md=1 attempt N/5 failed: …` — thermalmonitord still holding control.
   - `SMCWriter: F{n}Tg = N RPM` — actual target write.
   - `SMCWriter: Восстановление авто-режима …` — auto-restore triggered (intentional on SIGINT/Q/preset=0, unintentional if last XPC client disconnected).
   Live stream:
   ```
   log stream --predicate 'process == "BlikHelper"' --info
   ```
   Log rotates at 1 MB → `helper.log.old`.

6. **If `F{n}Md=1` retries keep failing — inspect thermalmonitord.**
   ```
   sudo launchctl list | grep thermal
   ```
   Should show `com.apple.thermalmonitord` running. If thermalmonitord is in a weird state, `F{n}Md` may stay at 3 indefinitely. Workarounds:
   - Wait longer than 5s (rare — usually 5s is enough on idle machine).
   - Restart thermalmonitord: `sudo launchctl kickstart -k system/com.apple.thermalmonitord`.
   - Reboot if persistent.

7. **Manual auto-restore (if app crashed mid-control).**
   Fans stuck at fixed RPM after a crashed `blik` / `BlikHelper`. Restore sequence:
   ```
   1. F{n}Md = 0  for EVERY fan in 0..<FNum  (not just tracked ones — orphan fans may be in mode=1)
   2. Ftst = 0                                (release back to thermalmonitord)
   ```
   In code this is `SMCWriter.restoreAutoMode(fanCount:)` — called on app start (safety net), on preset 0% (Auto), on `Q` key, on `SIGINT`/`SIGTERM`. For ad-hoc recovery: `sudo .build/debug/blik` then press `1` (preset 0%) or `Q`.

8. **Verify auto-restore on disconnect (XPC path).**
   When the last XPC client disconnects, `HelperDelegate` waits 5s and calls `restoreAutoMode`. If you see fans returning to auto unexpectedly while MenuBar app is open, suspect XPC connection drop — check `helper.log` for client connect/disconnect lines.

## Common issues

- **"Я нажал пресет, RPM не изменился, ошибки нет."** Almost always one of: (a) `Ftst=1` write skipped because already `ftstUnlocked` cached `true` but daemon was restarted and SMC state was reset — restart helper; (b) `dataAttributes` not propagated to write — check `writeKey()` did `readKeyInfo()` first; (c) FLT key written as FPE2 — check `dataType` branch in `setFanSpeed()`.
- **"Температуры показывают абсурдные значения."** FLT decoded as big-endian instead of little-endian. Apple Silicon SMC stores FLT little-endian. Symptom: huge numbers or zeros for keys like `TPDX`, `TCMz`, `Tg05`.
- **"`F{n}Md` stuck at 3 forever."** thermalmonitord did not release. See step 6.
- **"Кулеры возвращаются в auto через 5 секунд после закрытия CLI."** Intentional — `HelperDelegate` auto-restores when all XPC clients disconnect. Keep MenuBar app open or use `sudo blik` (direct SMC, no XPC).
- **"`sudo blik --diagnose` shows `Ftst=1` but app insists fans are in auto."** Previous run crashed before `restoreAutoMode`. Either rerun `sudo blik` (start does an unconditional auto-restore) or write `Ftst=0` manually via another tool.

## Where logs / metrics

- Helper daemon file log: `/Library/Logs/Blik/helper.log` (rotated to `helper.log.old` at 1 MB).
- Helper daemon syslog: `log stream --predicate 'process == "BlikHelper"' --info`.
- CLI log: `blik.log` in working directory (clear with `> blik.log`).
- MenuBar log: `os.Logger` subsystem `com.blik.menubar` — `log stream --predicate 'subsystem == "com.blik.menubar"'`.
- Raw SMC state: `sudo .build/debug/blik --diagnose` (point-in-time dump, no continuous metrics).
