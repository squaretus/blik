# Архитектура blik (macOS-приложение)

## Стек
- Swift 5.9+ (tools-version 5.9), Swift Package Manager, target macOS 26.0+ (Apple Silicon, протестировано на M4).
- SwiftUI (GUI + MenuBar, `@Observable @MainActor` VM-слой), NSXPCConnection (привилегированный daemon).
- SMC через IOKit — единственный процесс с прямым доступом — daemon `BlikHelper` (root).
- Локальная история метрик — SQLite (системная libsqlite3, линкуется в `BlikCore`, без package-зависимости).
- Внешние зависимости: `apple/swift-argument-parser` (CLI), `modelcontextprotocol/swift-sdk` (MCP-сервер в CLI).
- Приложение полностью бесплатное: серверное лицензирование, auth и телеметрия вырезаны (2026-07-13); сервер списан, лэндинг — GitHub Pages (`squaretus/blik-landing`), релизы и авто-апдейт — GitHub Releases `squaretus/blik`.

## Персистентность
Доменной БД нет. Единственное хранилище — локальный SQLite-кэш истории метрик (`/Library/Application Support/Blik/history.db`, пишет только daemon): таблицы `metric`/`sample_raw`/`sample_1m` с integer `metric_id` и композитными PK — time-series кэш, не сущности. Правило UUID-PK неприменимо. Preferences/имена метрик/конфиг графиков — в `UserDefaults(suiteName: "com.blik.shared")`.

## Сборка и запуск
```bash
swift build                    # Debug-сборка всех targets
swift build -c release         # Release
swift test                     # Тесты
scripts/build.sh 1.2.0         # PKG-установщик → .build/release_build/Blik-1.2.0.pkg
open /Applications/Blik.app    # GUI/MenuBar через XPC (после установки PKG)
blik                           # CLI TUI через XPC (без sudo)
blik claude-statusline         # ANSI-таблица метрик для статус-бара Claude Code
blik mcp                       # MCP-сервер (stdio) для Claude Code
sudo .build/debug/blik         # CLI напрямую через SMC (без установленного daemon'а)
```

## Структура (верхний уровень)
```
Sources/
├── BlikCore/     [library, +linkedLibrary("sqlite3")] SMC/, Model/, Resources/, History/ (SQLite), Logging/, Constants
├── BlikXPC/      [library] BlikHelperProtocol (@objc), XPCConstants, BlikXPCClient (sync-обёртки), UpdateService
├── BlikShared/   [library, @Observable VM-слой] AppCoordinator + VM + Charts/ + MetricNameStore
├── BlikDesign/   [library] Tokens/, Colors/, Icons/, Components/
├── BlikHelper/   [executable, root daemon] HelperDelegate, HistoryRecorder, UpdateChecker, ClientAuthorization, HelperLogger, main
├── blik/         [executable CLI] App/ (FanController, *DataSource), UI/ (ANSI TUI)
├── BlikMenuBar/  [executable SwiftUI MenuBarExtra]
└── BlikApp/      [executable SwiftUI GUI] Views/{Overview,Sensors,Resources,Charts,Preferences,MenuBar,Sidebar,Shared}
Tests/            BlikCoreTests, BlikXPCTests, BlikSharedTests, blikTests
```

Products (library): `BlikCore`, `BlikShared`, `BlikDesign`. Все 8 targets — см. индекс модулей.

## Индекс модулей
- [blik-core](../docs/modules/blik-core.md) — ядро: SMC (IOKit), модели (Fan/Sensor/Resource/Update/State), Resources (CPU/RAM/GPU/Disk reader + калькулятор), **History** (MetricKey, MetricSample, MetricSampleMapper, HistoryQuery, HistoryStore — SQLite-стор с raw/rollup/retention), Constants.
- [blik-xpc](../docs/modules/blik-xpc.md) — `@objc` XPC-протокол (fans/sensors/resources/state/update + **queryHistory/listHistoryMetrics**), `BlikXPCClient` sync-обёртки, `XPCConstants` (`protocolVersion`), `UpdateService`.
- [blik-shared](../docs/modules/blik-shared.md) — `@Observable @MainActor` VM: `AppCoordinator` (owns fan/resource/update/settings + `metricNames`/`charts`/`chartWidgets`), FanControlVM, ResourceVM, UpdateVM, AppSettingsVM, **MetricNameStore** (инлайн-переименование), **Charts/** (ChartsVM, ChartTimeRange, ChartWidgetConfig/Store, LiveMetricBuffer, MetricCatalog), `BlikRuntime` (lazy SMC/XPC + `helperSupportsHistory`).
- [blik-design](../docs/modules/blik-design.md) — токены (`DesignTokens`, `BlikPalette`, `AdaptiveColor`), `TemperatureColor`, `AppIcons`, компоненты (`BlikPageContainer`, `BlikBanner`, `BlikStatusPill`, `BlikPresetButtons`, `BlikSectionHeader`, `BlikSearch`, `BlikLogo`, `MenuBarImageRenderer`).
- [blik-helper](../docs/modules/blik-helper.md) — root daemon: `HelperDelegate` (SMC serial queue, reinforce timer, auto-restore, update), **`HistoryRecorder`** (2 serial-очереди sampling/db, ретенция, активен пока открыт клиент), `ClientAuthorization`, `UpdateChecker`, `HelperLogger`.
- [blik-cli](../docs/modules/blik-cli.md) — терминальный TUI (`FanController`, `XPCDataSource`/`SMCDataSource`, ANSI-рендер) + сабкоманды для Claude Code: `claude-statusline` (`StatuslineRenderer`), `mcp` (`BlikMCPTools`, `XPCMetricsSource`).
- [blik-menubar](../docs/modules/blik-menubar.md) — отдельный процесс MenuBarExtra (`FanDetailView`, `SensorSectionView`, `MenuBarLabel`).
- [blik-app](../docs/modules/blik-app.md) — GUI (`NavigationSplitView`): вкладки Обзор/Температура/**Ресурсы**/**Графики** (`SidebarTab`), Preferences (App/About), Charts/ UI (виджеты Swift Charts), Shared/ (`EditableMetricLabel`, `MetricSectionListPage`), Sidebar/.

## Ключевые контракты
- **VM:** `@Observable @MainActor final class`; XPC-callback'и приходят вне main → мутации оборачивать в `Task { @MainActor in ... }`. Внутри `@Observable` — `UserDefaults` напрямую (не `@AppStorage`).
- **Кнопки в content-слое:** `.buttonStyle(.borderedProminent)` + глобальный `.tint(DesignTokens.accent)` на корне `NavigationSplitView` (destructive → `.tint(DesignTokens.red)`). `.glass`/`.glassProminent` в content НЕ используем — Liquid Glass только на navigation layer.
- **Новые вкладки:** обязательно обёртка `BlikPageContainer` + `BlikPageMetrics.rowInsets` на каждую `Section`.
- **Шрифты:** только `DesignTokens.fontPrimary`/`fontPrimaryMedium`/`fontSecondary`. Числа в `Text` → `Text(verbatim:)`.
- **XPC:** `@objc`-протокол, данные — JSON-encoded `Data`; версия XPC-протокола `XPCConstants.protocolVersion` (сейчас 2.11.0) развязана с релизной (`build.sh` подставляет только `appVersion`), бампается вручную при изменении XPC-поверхности; range-режим графиков гейтится `BlikRuntime.helperSupportsHistory` (`Constants.minHelperVersionForHistory`), гейты не поднимать выше `protocolVersion` (инвариант — `XPCProtocolVersionTests`).
- **История:** все чтения истории — только через XPC (root-owned WAL-БД нечитаема из user-процессов); хелпер клампит `maxPointsPerSeries ≤ 2000`, `metrics ≤ 32`.
- **MenuBarExtra:** гейт `isPresented` в `MenuBarPopupView` — фикс утечки observation, не трогать.

## Управление кулерами (M4) — критично
1. `Ftst=1` (unlock от thermalmonitord, однократно) → 2. пауза ~5с (`F{n}Md`: 3→0) → 3. `F{n}Md=1` (forced, retry до 5) → 4. `F{n}Tg=RPM` → 5. `reinforceSpeed()` каждую секунду. `writeKey()` обязательно вызывает `readKeyInfo()` (иначе SMC молча игнорирует запись). Восстановление auto: `F{n}Md=0` для всех → `Ftst=0` (при старте, пресете 0%, выходе, SIGINT/SIGTERM). Пресеты 0/25/50/75/100% меняют все кулеры одновременно.

### Базовый образ

Отсутствует — проект не использует пред-собранный base image для кэша зависимостей (нативное macOS-приложение SPM + PKG-установщик, без Docker).
