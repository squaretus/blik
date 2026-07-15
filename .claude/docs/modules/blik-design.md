# BlikDesign

## Purpose
Pure-UI design system library shared by the two SwiftUI surfaces of Blik — `BlikApp` (GUI) and `BlikMenuBar` (tray app). Owns the brand palette, design tokens (colors, fonts, sizes), temperature color heuristics, SF Symbol wrappers, the page-level layout container, and a small set of SwiftUI primitives that don't have a native macOS 26 equivalent. Leaf module by construction: depends only on SwiftUI/AppKit, never on `BlikCore`, `BlikXPC`, `BlikShared`, or any domain model. Consumers must reuse these tokens/components instead of hardcoding colors, fonts, paddings, or rebuilding banner/status-pill primitives — this is the single point of customization for the brand surface. <!-- BlikSubscriptionGate was removed when the app went fully free (2026-07-13) — no gate component remains -->

## Key files
- `Sources/BlikDesign/Tokens/BlikPalette.swift`
- `Sources/BlikDesign/Tokens/DesignTokens.swift`
- `Sources/BlikDesign/Tokens/AdaptiveColor.swift`
- `Sources/BlikDesign/Tokens/Color+Hex.swift`
- `Sources/BlikDesign/Colors/TemperatureColor.swift`
- `Sources/BlikDesign/Icons/AppIcons.swift`
- `Sources/BlikDesign/Components/BlikPageContainer.swift`
- `Sources/BlikDesign/Components/BlikBanner.swift`
- `Sources/BlikDesign/Components/BlikStatusPill.swift`
- `Sources/BlikDesign/Components/BlikPresetButtons.swift`
- `Sources/BlikDesign/Components/BlikSectionHeader.swift`
<!-- removed: `Sources/BlikDesign/Components/BlikSubscriptionGate.swift` (was BlikLicenseGate.swift) — deleted, app fully free -->
- `Sources/BlikDesign/Components/BlikLogo.swift`
- `Sources/BlikDesign/Components/BlikSearch.swift`
- `Sources/BlikDesign/Components/MenuBarImageRenderer.swift`

## Entry points

Tokens / palette:
- `BlikPalette.primary` (`#007479`), `.light` (`#2FB3B8`), `.deep` (`#003C40`), `.mintMid` (`#7FDCDE`), `.mintGlass` (`#CBF3F2`) — theme-independent brand colors
- `BlikPalette.Theme` struct — full per-theme tuple (`bg / surface / surface2 / text / muted / line / accent / statusOK / statusWarn / statusError / statusSuccess`)
- `BlikPalette.darkTheme`, `.lightTheme`, `.theme(_ scheme: ColorScheme) → Theme`
- `BlikPalette.bg / surface / surface2 / text / muted / line / accent / statusOK / statusWarn / statusError / statusSuccess : AdaptiveColor` — adaptive aliases for use-cases without a live `ColorScheme`
- `DesignTokens.accent` (= `BlikPalette.accent`), `.accentDark` (= `darkTheme.accent`), `.accentLight` (= `lightTheme.accent`)
- `DesignTokens.green` (`#00D68F`), `.amber` (`#FFB300`), `.amberDark` (`#E07700`, hardcoded — not from palette), `.red` (`#FF4D6D`)
- `DesignTokens.textSecondary`, `.textTertiary : AdaptiveColor` (opacity-based)
- `DesignTokens.fontPrimary` (`.system(size: 13, weight: .regular)`), `.fontPrimaryMedium` (13pt medium), `.fontSecondary` (11pt regular — declared, currently unused)
- `DesignTokens.windowMinWidth = 900`, `.windowMinHeight = 600`, `.progressBarHeight = 6`, `.progressBarBg : AdaptiveColor`
- `AdaptiveColor(dark:light:).resolve(_ scheme: ColorScheme) → Color`
- `Color.init(hex: UInt, opacity: Double = 1.0)` — `0xRRGGBB` extension on `SwiftUI.Color`

Temperature heuristics:
- `TemperatureColor.color(for: Double) → Color` — thresholds: `<60` green, `60..<75` amber, `75..<85` amberDark, `≥85` red
- `TemperatureColor.gradient(for: Double) → LinearGradient` — `>60` amber→amberDark (top→bottom), else `#6EE7B7`→green
- `TemperatureColor.ambientGlow(for: Double) → Color` — `>60` amberDark@0.15, else green@0.12
- `TemperatureColor.fanGradient(percentage: Double) → LinearGradient` — `>0.6` green→amber (leading→trailing), else green→green; expects `0.0..1.0`
- `TemperatureColor.fanGlowColor(percentage: Double) → Color` — `>0.6` amber@0.3, else green@0.3

Icons (all SF Symbols, fixed weights and sizes):
- `AppIcons.GridIcon` — `square.grid.2x2`, 14pt regular
- `AppIcons.ThermometerIcon` — `thermometer.medium`, 14pt regular
- `AppIcons.SettingsIcon` — `gearshape`, 14pt regular
- `AppIcons.SidebarIcon` — `sidebar.left`, 13pt regular
- `AppIcons.FanIcon` — `fanblades`, 12pt regular

Layout / page caркас:
- `BlikPageContainer<Content: View> { content }` — single tab-content wrapper
- `BlikPageMetrics.topPadding` (`0`), `.horizontalPadding` (`40`), `.rowInsets` (`top: 8, leading: 0, bottom: 8, trailing: 0`), `.sectionSpacing` (`20`) — vertical gap between categories, applied as a clear-color footer spacer on each `Section` (`.listSectionSpacing` is unavailable on macOS)

Primitives:
- `BlikBanner<Trailing: View>(tone: Tone, systemImage: String?, text: String, trailing: () -> Trailing = EmptyView)` — `Tone = .info | .warn | .error | .success | .accent`; background `.regularMaterial` in `RoundedRectangle(cornerRadius: 10)`; text font `.callout`; only the icon picks up tone color (text stays `.secondary`)
- `BlikStatusPill(text: String, color: Color, filled: Bool = false)` — capsule with `12×6` padding, `fontPrimaryMedium`; `filled=true` → solid fill + white text; `filled=false` → `color@0.12` fill + `color@0.15` stroke + `color` text
- `BlikPresetButtons(currentPreset: Int, presets: [Int] = [0,25,50,75,100], autoLabel: String = "Авто", size: Size = .regular, onSelect: (Int) -> Void)` — `Size = .regular | .compact` (maps to `.controlSize(.regular | .small)`); preset `0` shown as `autoLabel`, others as `"N%"`; wraps `Picker(.segmented)`
- `BlikSectionHeader<Trailing: View>(_ text: String, trailing: () -> Trailing = EmptyView)` — uppercase 9pt header (`.system(size: 9)`), tracking `0.08 * 9 = 0.72`, color `textTertiary`
<!-- removed: BlikSubscriptionGate entry point — component deleted, app fully free -->
- `BlikLogo(size: Size = .md, glow: Bool = false)` — brand orb-dot + monospaced "blik" wordmark; `Size = .sm | .md | .lg | .xl` controls orb size/font/spacing; `glow=true` adds radial halo for hero/landing contexts

Search:
- `EnvironmentValues.searchQuery: String` (default `""`) — single global search field value
- `View.searchVisible(matches: [String]) → some View` — visibility filter; row is rendered only when `searchQuery` is empty (after trim) or **any** match in `matches` contains the query case-insensitively
- `View.searchVisible(_ match: String) → some View` — shortcut for one string

Menu-bar image:
- `MenuBarImageRenderer.image(fan0: Int?, fan1: Int?, temp: Int?) → NSImage` — caching public API; key = `"<fan0>|<fan1>|<temp>"`; `nil` renders as `"— RPM"` / `"—°C"`; returned image has `isTemplate = true`

## Dependencies
- SwiftUI — tokens + all components except `MenuBarImageRenderer`
- AppKit (`NSImage`, `NSFont`, `NSColor`, `NSAttributedString`, `NSLock`) — only in `MenuBarImageRenderer`
- No project-internal dependencies. `BlikDesign` is a SPM leaf library (`Package.swift`: `.target(name: "BlikDesign", path: "Sources/BlikDesign")` — no `dependencies` array).
- Consumers (declared in `Package.swift`): `BlikApp`, `BlikMenuBar`. Not consumed by `blik` (CLI) or `BlikHelper` (daemon).

## Side effects
<!-- generated, verify -->
- `MenuBarImageRenderer` maintains a process-local LRU cache (`cache: [String: NSImage]`, `order: [String]`, `cacheLimit = 128`) guarded by an `NSLock`. Eviction is FIFO-by-insertion (oldest key in `order` is removed when capacity is exceeded). Entries are never invalidated by time or by external signal.
- `MenuBarImageRenderer.render` performs `NSImage.lockFocus()` / `unlockFocus()` and Core Graphics text drawing via `NSAttributedString.draw(at:withAttributes:)`. AppKit's drawing contract requires this on the main thread; callers from XPC callback queues must hop via `Task { @MainActor in … }` first.
- The rendered image is marked `isTemplate = true` so AppKit tints it for the menu-bar appearance (light/dark/accent).
- No disk I/O, no network, no `UserDefaults`, no `NotificationCenter`, no XPC, no SMC.
- No global mutable state outside the renderer cache. Tokens / palette / temperature / icons / banner / pill / preset / header / search are pure value-producing — they hold only `let` properties and computed views.

## Invariants / assumptions
<!-- generated, verify -->
- **Brand palette is a port of `icon/blik/palette/palette.json`.** Header comment in `BlikPalette.swift` declares the JSON file (with companion `palette.css`) as the single source of truth for the brand. Any change to the JSON must be re-ported into `BlikPalette.swift` — and vice versa — by hand. There is no codegen between them.
- **`DesignTokens.amberDark` (`#E07700`) is NOT in the palette JSON.** It is a Swift-only constant introduced for the 75–85°C "hot" temperature band. If the canonical palette is ever extended to cover this band, this constant should be migrated into `BlikPalette` so both sides agree.
- **`BlikPageContainer` is the only legitimate page-level layout wrapper** for tab pages (`Обзор`, `Температура`, `Настройки`). Pages must not hardcode horizontal or top padding, must not set their own background, and must apply `BlikPageMetrics.rowInsets` to every `Section`, and (for inter-category spacing) add a `Color.clear.frame(height: BlikPageMetrics.sectionSpacing)` footer to each `Section`. **Inter-category divider lines are suppressed** — pages apply `.listRowSeparator(.hidden)` to every row, header, and footer (incl. the spacer); the only inter-category separation is the `sectionSpacing` footer gap, no hairline. Scroll primitive is always `List { Section }` — the container's `.scrollContentBackground(.hidden)` + `.listStyle(.plain)` are tuned for `List`, not `Form`. Doc-comment inside `BlikPageContainer.swift` already mentions "форма/лист" in passing; only `List` is supported in practice. **Horizontal inset is applied via `.contentMargins(.horizontal, BlikPageMetrics.horizontalPadding, for: .scrollContent)`, NOT `.padding(.horizontal)`** — `.padding` narrows the scroll primitive itself so the scroll indicator draws `horizontalPadding` pt inside the window edge; `contentMargins` insets only the content and keeps the scrollbar at the window edge. Affects all tabs. See bugs/charts-scroll-freeze-observable-bypass.md.
- **`BlikPageContainer` deliberately does NOT touch safe-area.** `NavigationSplitView` already reserves the traffic-lights region; calling `.ignoresSafeArea(.container, edges: .top)` from a page breaks sidebar rendering. `BlikPageMetrics.topPadding = 0` is intentional.
- **Global `.tint` is applied externally**, not by this module. `BlikApp` puts `.tint(DesignTokens.accent)` on the `NavigationSplitView` root; both `.borderedProminent` action buttons and the `Picker(.segmented)` selection inherit it. Components in `BlikDesign` only consume `DesignTokens.accent` (e.g. `BlikBanner.accent` icon color); they don't set `.tint` on themselves.
- **Liquid Glass is content-layer-forbidden.** Per project rules in `.claude/CLAUDE.md`, glass styles (`.glass`, `.glassProminent`, `.glassEffect`) are reserved for the navigation layer (sidebar / toolbar / scroll edge fade / floating glass). Any component in this module that introduces an action button must hard-wire `.buttonStyle(.borderedProminent)`, not a glass style.
- **Typography is monolithic at 13pt.** `DesignTokens.fontPrimary` is the single primary size for the whole app (labels, body, buttons, sidebar). `fontPrimaryMedium` is reserved for interactive elements. `fontSecondary` (11pt) is declared but unused. Pages and components must not use `.callout` / `.caption` / `.system(size:)` directly — exception: `BlikBanner` uses `.font(.callout)` and `BlikSectionHeader` uses `.system(size: 9)` (these are intentional in-module exceptions, see Failure hotspots).
- **`TemperatureColor` thresholds (`<60`, `60..<75`, `75..<85`, `≥85`) are CPU/GPU thermal heuristics** chosen for Apple Silicon (M4). Changing them is a UX decision, not a refactor.
- **`TemperatureColor.fanGradient` and `.fanGlowColor` expect `percentage ∈ [0.0, 1.0]`**, not `[0, 100]` (compared to `0.6`).
- **`searchVisible` is a visibility filter, not a highlighter.** When the query has no match, the modifier returns an empty `Group`, removing the row from the view tree. `matches` must include both RU and EN variants needed for the page (project convention) and at minimum the visible label.
- **`EnvironmentValues.searchQuery` has a single producer.** Only `MainContentView` in `BlikApp` writes it via `.searchable(...)` + `.environment(\.searchQuery, ...)` forwarding into the detail pane. All other readers treat empty (after trim) as "no filter".
- **`MenuBarImageRenderer.image` is the only sanctioned way to draw the menu-bar tray icon.** Passing `nil` for any of `fan0 / fan1 / temp` signals unavailable fan data (e.g. daemon not connected) — the renderer draws `— RPM` / `—°C`. Two-fan layouts pass both `fan0` and `fan1`; single-fan layouts pass `fan1: nil` and the `line0` is centered vertically.
- **`BlikPalette` adaptive aliases (`.bg`, `.accent`, …) are `AdaptiveColor`, not `Color`.** Consumers that need a concrete `Color` call `.resolve(colorScheme)` against the current `@Environment(\.colorScheme)`. This module never reads `NSApplication.shared.effectiveAppearance` directly.

## Failure hotspots
<!-- generated, verify -->
- **`MenuBarImageRenderer.render` must run on the main thread** (AppKit drawing contract). Calling it from a background queue can produce blank or corrupted images and intermittent crashes inside `lockFocus()`. Polling Tasks in `BlikShared.FanControlVM` should already be `@MainActor`-bound, but XPC reply blocks come back on the XPC queue — any new caller hopping data into the renderer must `Task { @MainActor in … }` first.
- **LRU cache key in `MenuBarImageRenderer` collapses on the exact tuple `(fan0, fan1, temp)`.** If a caller passes wildly varying values every tick (e.g. raw RPMs at full precision rather than rounded integers), the cache churns through the 128-entry limit and provides no benefit. Consumers must pass already-rounded integers.
- **Cache is never invalidated by `colorScheme` change.** Images are template (`isTemplate = true`), so AppKit re-tints automatically — but if the rendering code ever stops using `isTemplate`, the cache will start serving stale per-theme bitmaps. Watch for this if `render()` is modified to inject color directly.
- **`BlikPageContainer` resolves `BlikPalette.bg` against `@Environment(\.colorScheme)` only on its own subtree.** Embedding the container inside another material-backed scene (sheet, popover, secondary window) can produce a double-fill where the outer material is darkened by the inner `bg`. Pages outside the main `NavigationSplitView` should not use this container.
- **`TemperatureColor.fanGradient(percentage:)` silently degrades to "all-green" if percentage is in `[0, 100]` instead of `[0.0, 1.0]`.** The branch always takes `> 0.6` when given `> 0.6` of either domain, but a value of `25` (intended 25%) is also `> 0.6`, hitting the wrong gradient. Wrong-domain bugs here are silent — no assertion.
- **`BlikStatusPill` hardcodes `12×6` padding and `fontPrimaryMedium`.** The pill is sized by its text; long labels (multi-word statuses) break it into oddly wide capsules. There is no `lineLimit` or truncation. Keep labels short.
- **`BlikSectionHeader` uses `.system(size: 9)` directly**, not a `DesignTokens.fontSecondary` token. `fontSecondary` is 11pt — even if it were applied, sizes would diverge. If typography is later normalized via tokens, this is the file that will drift away first.
- **`BlikBanner` text uses `.font(.callout)`**, not `DesignTokens.fontPrimary` (13pt). Intentional — banner is treated as a navigation-layer-ish element with a material background — but it's a deliberate divergence and the only one in this module outside `BlikSectionHeader`.
- **`searchVisible` removes the row from the view tree**, it doesn't fade it out. Identity-sensitive constructs inside the row (animations, transitions, `@State` that the user expects to persist while typing) reset every time the query toggles visibility on/off. Use sparingly on stateful rows.
- **`AppIcons` fixes font sizes per icon** (`14 / 14 / 14 / 13 / 12`). They are not tied to `DesignTokens.fontPrimary`; bumping the global font size will not affect icon glyphs. Sidebar and toolbar layout assumes these specific sizes.
- **`BlikPalette.darkTheme.accent` and `lightTheme.accent` are NOT the same color** (`#2FB3B8` vs `#007479`). `DesignTokens.accent` resolves through `AdaptiveColor`, so consumers using the adaptive alias get the right one. Consumers that import `BlikPalette.darkTheme.accent` directly will hardcode the dark variant in both themes — easy to write, hard to spot in screenshots.
- **`Package.swift` does NOT expose `BlikDesign` test target.** There is no `BlikDesignTests` directory. Regressions in pure-UI tokens are caught only by visual inspection.

## Related docs
- modules/blik-app.md
- modules/blik-menubar.md
- modules/blik-shared.md
- modules/blik-core.md
