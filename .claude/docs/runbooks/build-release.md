# Build & Release

End-to-end procedure for producing a signed `Blik-<VERSION>.pkg` installer and publishing it as a GitHub Release in the single repo `squaretus/blik` (both build location and auto-update source).

## Summary

<!-- generated, verify -->

A single command — `scripts/build.sh <VERSION>` — patches version strings into the source tree, performs a SwiftPM release build of all three executables (`BlikApp`, `blik`, `BlikHelper`), assembles `Blik.app`, lays out the PKG payload (`/Applications`, `/Library/PrivilegedHelperTools`, `/Library/LaunchDaemons`, `/Library/LaunchAgents`, `/usr/local/bin`), runs `pkgbuild` + `productbuild`, and drops `.build/release_build/Blik-<VERSION>.pkg`. On `git push --tags` matching `v*`, `.github/workflows/release.yml` runs the same script on `macos-26`, and attaches the PKG to a GitHub Release in `squaretus/blik` — the same repo polled by the in-app auto-updater.

## Steps

### Local build

1. From the repo root, run `scripts/build.sh 1.3.0` (substitute the target version).
   - The script `set -euo pipefail`s; first failure aborts.
   - Defaults to `1.0.0` if no argument is passed.

2. **Version substitution.** The script edits in place via `sed -i ''`:
   - `Sources/BlikCore/Constants.swift` — `public static let appVersion = "..."`
   - `Resources/Blik-Info.plist` and `Resources/BlikApp-Info.plist` — every `<string>X.Y.Z</string>` is rewritten (covers both `CFBundleVersion` and `CFBundleShortVersionString`).
   - **`Sources/BlikXPC/XPCConstants.swift` is NOT touched.** `protocolVersion` (formerly `helperVersion`) is the XPC-protocol capability level, not the release version, and is bumped manually only when the XPC surface changes. The old `sed` on this file caused the release-version-vs-protocol-gates regression (a release version below `minHelperVersionFor*` made a fresh helper fail its own capability gates → «история недоступна» + legacy live-polling). See bugs/release-version-vs-protocol-gates.md.
   - These edits land in the working tree and are **not** reverted by the script — commit or `git checkout --` them yourself afterwards.

3. **SwiftPM release builds** (sequential):
   - `swift build -c release --product BlikApp`
   - `swift build -c release --product blik`
   - `swift build -c release --product BlikHelper`

4. **`Blik.app` assembly** under `.build/release_build/_app/Blik.app/Contents`:
   - `MacOS/BlikApp` ← `.build/release/BlikApp`
   - `Info.plist` ← `Resources/BlikApp-Info.plist`
   - `Resources/uninstall-helper.sh` (+ `chmod +x`)
   - `Resources/AppIcon.icns`
   - SPM resource bundle `blik_BlikApp.bundle` copied **twice** (into `Contents/Resources/` and into `.app/` root — `Bundle.module` lookup tolerates either location; failures are swallowed via `|| true`).
   - Ad-hoc codesign: `codesign --force --sign - --deep Blik.app` (errors swallowed).

5. **PKG payload** assembled under `.build/release_build/_pkg-root/`:
   - `Applications/Blik.app/` ← bundle from step 4
   - `Library/PrivilegedHelperTools/com.blik.helper` ← `.build/release/BlikHelper`
   - `Library/LaunchDaemons/com.blik.helper.plist` ← `Resources/com.blik.helper.plist`
   - `Library/LaunchAgents/com.blik.app.plist` ← `Resources/com.blik.app.plist`
   - `usr/local/bin/blik` ← `.build/release/blik`

6. **Scripts payload** under `.build/release_build/_pkg-scripts/`:
   - `preinstall` (kills `BlikMenuBar`, `bootout`s the LaunchAgent + LaunchDaemon).
   - `postinstall` (chowns helper to `root:wheel`, `bootstrap`s the daemon system-wide and the agent into the GUI user's domain; falls back to `open /Applications/Blik.app` if `bootstrap` no-ops because the agent is already registered).
   - Both `chmod +x`.

7. **`pkgbuild`** → `_component.pkg`:
   - `--identifier com.blik.pkg`, `--version <VERSION>`, `--install-location /`.

8. **`productbuild`** with a generated `_distribution.xml`:
   - Welcome (`Resources/welcome.html`) + conclusion (`Resources/conclusion.html`) pages.
   - `hostArchitectures="arm64"`, `os-version min="13.0"` (note: app's `LSMinimumSystemVersion` is `26.0` — the PKG itself installs on 13+, but the binary refuses to launch on older systems).
   - `customize="never"` → no component picker, single default choice.
   - Final artifact: `.build/release_build/Blik-<VERSION>.pkg`.

9. **Cleanup.** All `_app/`, `_pkg-root/`, `_pkg-scripts/`, `_pkg-resources/`, `_distribution.xml`, `_component.pkg` intermediates are removed; only `Blik-<VERSION>.pkg` survives in `release_build/`.

### Install / verify locally

```bash
open .build/release_build/Blik-<VERSION>.pkg
```

Final on-disk layout after install (mirrors ARCHITECTURE.md «Сборка и установка»):

| Path | Source |
|---|---|
| `/Applications/Blik.app` | unified GUI + MenuBar app |
| `/Library/PrivilegedHelperTools/com.blik.helper` | root LaunchDaemon binary |
| `/Library/LaunchDaemons/com.blik.helper.plist` | `KeepAlive=true`, `RunAtLoad=true`, MachService `com.blik.helper` |
| `/Library/LaunchAgents/com.blik.app.plist` | `RunAtLoad=true`, `KeepAlive=false` — login autostart |
| `/usr/local/bin/blik` | CLI (XPC client) |

### CI release (GitHub Actions)

Trigger: `git push origin vX.Y.Z` (tag matching `v*`).

Workflow `.github/workflows/release.yml`, runs on `macos-26`:

1. Checkout (`actions/checkout@v4`).
2. Extract `VERSION` from `GITHUB_REF_NAME` (strips leading `v`).
3. Run `scripts/build.sh "$VERSION"`.
4. **Create release** (single step `Create release`) in `squaretus/blik` via `softprops/action-gh-release@v2`, named `Blik <VERSION>`, with auto-generated release notes from commit history. This is the release URL polled by `BlikHelper.UpdateChecker` every 6h for auto-update — there is no separate public mirror repo.

## Common issues

<!-- generated, verify -->

- **`sed` edits left in working tree.** After a local build, `git status` will show modified `Constants.swift`, `Blik-Info.plist`, `BlikApp-Info.plist`. `XPCConstants.swift` is **not** modified by the build anymore. Commit deliberately or revert with `git checkout --`.
- **Bumping `XPCConstants.protocolVersion`.** Only when the XPC surface changes (new/changed protocol methods or payload contracts). When raising a `Constants.minHelperVersionFor*` gate, bump `protocolVersion` to at least that value first — a gate above the current `protocolVersion` makes freshly built helpers fail their own capability checks (`XPCProtocolVersionTests` guards this).
- **Ad-hoc codesign only.** `codesign --sign -` produces a locally trusted, non-Developer-ID signature. Gatekeeper will prompt on first launch on a fresh machine. For notarised distribution, this step needs a real identity + `notarytool`.
- **App refuses to launch on macOS < 26.** `LSMinimumSystemVersion=26.0` in `BlikApp-Info.plist` despite the PKG accepting macOS 13+. Don't downgrade the plist without verifying SwiftUI APIs used (NavigationSplitView Liquid Glass effects, `.glassEffect`, etc. are 26-only).
- **Daemon doesn't restart after install.** `postinstall` calls `launchctl bootstrap system /Library/LaunchDaemons/com.blik.helper.plist`. If a previous `bootout` (from `preinstall`) raced with the new bootstrap, the daemon may be in a stuck state — `launchctl print system/com.blik.helper` shows the current state; manual fix is `bootout` + `bootstrap`.
- **MenuBar app doesn't appear after install.** `postinstall` has a fallback `open /Applications/Blik.app` if `pgrep -x BlikMenuBar` doesn't find a process within 1s. If even that fails, user needs to launch from `/Applications` manually (first run only).

## Where logs / metrics

- Local build output: stdout of `scripts/build.sh` (no log file).
- CI build output: GitHub Actions UI → `Release` workflow → `Build PKG & Publish Release` job.
- Installer logs (post-install on user machine): `/var/log/install.log`.
- Daemon runtime logs after install: `/Library/Logs/Blik/helper.log` (see `Sources/BlikHelper/HelperLogger.swift`).
- Public release URL (auto-update source): `https://github.com/squaretus/blik/releases/latest`.

## Related docs

- `.claude/rules/ARCHITECTURE.md` — section «Сборка и установка», «Автообновление (Daemon-Centric)»
- `.claude/CLAUDE.md` — section «Сборка и запуск», «Автообновление»
