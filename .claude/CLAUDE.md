# blik — Мониторинг системы и управление вентиляторами для Mac на Apple Silicon

## Стек
- Swift 5.9+, Swift Package Manager
- macOS 26.0+ (Apple Silicon, протестировано на M4); Liquid Glass design language
- SwiftUI (GUI app + MenuBar app, `@Observable @MainActor`), NSXPCConnection (XPC)
- Локальная история метрик — SQLite (системная libsqlite3, линкуется в `BlikCore`)
- Зависимости: `apple/swift-argument-parser` (CLI target)
- Приложение полностью бесплатное: серверного лицензирования, auth и телеметрии в коде нет (вырезаны 2026-07-13; сервер списан, остался только лэндинг на GitHub Pages)

## Сборка и запуск
```bash
swift build                                        # Debug-сборка всех targets
swift build -c release                             # Release-сборка
swift test                                         # Тесты

# Сборка PKG-установщика (VERSION подставляется в Constants.swift, XPCConstants.swift, Info.plist)
scripts/build.sh 1.2.0                             # Результат: .build/release_build/Blik-1.2.0.pkg

# CLI (терминальный режим, с sudo — прямой SMC)
sudo .build/debug/blik                           # Полное управление
.build/debug/blik --read-only                    # Мониторинг (без sudo)
.build/debug/blik --once                         # Однократный вывод
sudo .build/debug/blik --diagnose                # Диагностика SMC-ключей
.build/debug/blik --update                       # Проверка и установка обновления (через XPC)

# MenuBar app (с sudo — прямой SMC)
sudo .build/debug/BlikMenuBar                    # Полное управление
.build/debug/BlikMenuBar                         # Read-only мониторинг

# После установки PKG — CLI и MenuBar работают без sudo (через XPC daemon)
blik                                             # TUI через XPC
open /Applications/Blik.app                      # MenuBar через XPC
```

## Targets
- `BlikCore` — библиотека (SMC, модели, Resources, **History** — SQLite-стор, константы). Линкует системную `libsqlite3` (`linkerSettings: [.linkedLibrary("sqlite3")]`), без package-зависимостей
- `BlikXPC` — библиотека (XPC протокол + клиент; методы истории `queryHistory`/`listHistoryMetrics`), зависит от BlikCore
- `BlikShared` — библиотека (`@Observable` VM-слой: AppCoordinator + FanControlVM/ResourceVM/UpdateVM/AppSettingsVM + **MetricNameStore** + **Charts/** + BlikRuntime), зависит от BlikCore + BlikXPC
- `BlikDesign` — библиотека (UI токены/компоненты/иконки; кнопки — нативный `.borderedProminent`)
- `BlikHelper` — привилегированный LaunchDaemon (root; HelperDelegate + **HistoryRecorder** + ClientAuthorization + UpdateChecker), зависит от BlikCore + BlikXPC
- `blik` — CLI executable, зависит от BlikCore + BlikXPC + ArgumentParser
- `BlikMenuBar` — MenuBar app (SwiftUI), зависит от BlikCore + BlikXPC + BlikShared + BlikDesign
- `BlikApp` — GUI app (SwiftUI, NavigationSplitView), зависит от BlikCore + BlikXPC + BlikShared + BlikDesign

## Структура
- `Sources/BlikCore/SMC/` — работа с SMC через IOKit (бинарный протокол, чтение/запись)
- `Sources/BlikCore/Model/` — модели данных (FanInfo, SensorInfo, ResourceModels, StateSnapshot, UpdateInfo)
- `Sources/BlikCore/Resources/` — чтение CPU/RAM/GPU/Disk (ResourceReader, ResourceUsageCalculator, CPUTopology)
- `Sources/BlikCore/History/` — **локальная история метрик**: `MetricKey` (стабильные ID метрик), `MetricSample`, `MetricSampleMapper` (fans/sensors/reading → сэмплы), `HistoryQuery` (XPC-контракт), `HistoryStore` (SQLite: raw/rollup/retention)
- `Sources/BlikCore/Constants.swift` — именованные константы (GitHub repo, интервалы, `minHelperVersionForHistory`, history-константы)
- `Sources/BlikXPC/` — XPC протокол (BlikHelperProtocol, +`queryHistory`/`listHistoryMetrics`), XPCConstants (`helperVersion`), клиент (sync-обёртки), UpdateService
- `Sources/BlikShared/` — `@Observable @MainActor` VM-слой: `AppCoordinator` + `FanControlVM`/`ResourceVM`/`UpdateVM`/`AppSettingsVM` + `MetricNameStore` (инлайн-переименование метрик) + `Charts/` (ChartsVM, ChartTimeRange, ChartWidgetConfig/Store, LiveMetricBuffer, MetricCatalog) + `BlikRuntime` (lazy SMC/XPC + `helperSupportsHistory`)
- `Sources/BlikDesign/` — токены (`DesignTokens`, `BlikPalette`, `AdaptiveColor`), компоненты (`BlikBanner`, `BlikStatusPill`, `BlikPresetButtons`, `BlikSectionHeader`, `BlikSearch`, `BlikPageContainer`, `BlikLogo`, `MenuBarImageRenderer`), цвета температуры
- `Sources/BlikHelper/` — привилегированный daemon (HelperDelegate, **HistoryRecorder** — запись истории пока открыт клиент, ClientAuthorization, UpdateChecker, HelperLogger, main.swift)
- `Sources/blik/UI/` — терминальный UI (ANSI escape codes, termios)
- `Sources/blik/App/` — логика CLI (FanController, XPCDataSource/SMCDataSource/FanDataSource, SignalHandler, Logger)
- `Sources/BlikMenuBar/` — SwiftUI MenuBar app (использует `BlikShared.AppCoordinator`)
- `Sources/BlikApp/` — SwiftUI GUI app (NavigationSplitView; вкладки Обзор/Температура/Ресурсы/**Графики**; Views/Preferences (App/About), Views/Charts, Views/Shared, Views/Sidebar; использует `BlikShared.AppCoordinator`)
- `Resources/` — plists (Info, LaunchDaemon, LaunchAgent), HTML визарда, скрипт удаления
- `scripts/` — build.sh (сборка PKG), preinstall/postinstall (скрипты PKG)
- `Tests/BlikCoreTests/` — тесты ядра (конверсии, модели, History: HistoryStore/MetricSampleMapper/HistoryQueryModels)
- `Tests/BlikSharedTests/` — тесты VM (FanControlVM, UpdateVM, MetricNameStore, ChartWidgetStore, LiveMetricBuffer, ChartsVM)
- `Tests/blikTests/` — тесты CLI (ANSI stripping, keyboard)

## Паттерны
- Файл с `@main` называется `Blik.swift` / `BlikMenuBarApp.swift` / `BlikAppMain.swift` (не `main.swift` — конфликт с `@main`). Исключение: `BlikHelper/main.swift` (нет `@main`, используется `dispatchMain()`)
- **State management:** все VM-классы помечаются `@Observable @MainActor final class`. XPC callbacks приходят с XPC-очереди — внутри callback'а **обязателен** `Task { @MainActor in ... }` перед мутацией `@Observable` свойств
- **Polling:** `Task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(interval)); ... } }` запускается в init VM, отменяется в deinit. Sleep/wake — `addObserver` на `NSWorkspace.willSleepNotification`/`didWakeNotification` с stored token, отменяет/перезапускает polling Task (НЕ через async sequence: `Notification` не Sendable под Swift 6)
- **Cross-process navigation BlikMenuBar → BlikApp:** URL scheme `blik://<tab>` (rawValue `SidebarTab`: `blik://overview|temperature|resources|charts`, а также `blik://settings`) через `NSWorkspace.shared.open(...)` + `.onOpenURL` на `Window` + AppDelegate `application(_:open:)` backstop для cold-start. **`Window` НЕ поддерживает `.handlesExternalEvents`** — только `.onOpenURL`
- **Кнопки в content слое:** `.buttonStyle(.borderedProminent)` для всех action-кнопок (внутри `Section` row, `BlikBanner`). Глобальный `.tint(DesignTokens.accent)` на корне `NavigationSplitView` подхватывается → solid accent fill + белый текст, согласованно с selected segment в Picker(.segmented) и selected pill в сайдбаре. Destructive — `.buttonStyle(.borderedProminent).tint(DesignTokens.red)`. **`.glass`/`.glassProminent` НЕ используем в content** — на macOS 26 в `Section` row они рендерятся плоско-полупрозрачно, теряют белый текст и не совпадают визуально с системными элементами выделения. Liquid Glass остаётся только на navigation layer: `.scrollEdgeEffectStyle(.soft, for: .top)` на List, `.glassEffect(.regular, in: .capsule)` на toolbar search field, автоматический glass на сайдбаре `NavigationSplitView`
- **`@AppStorage` НЕ работает внутри `@Observable` класса** — для preferences в VM использовать `UserDefaults` напрямую с `didSet` или оставлять `@AppStorage` в самих view'ах
- SMC данные в форматах: FPE2 (fan RPM, big-endian), SP78 (температура), FLT (float, **little-endian** на Apple Silicon)
- Терминал переводится в raw mode через termios, восстанавливается при выходе
- SIGINT/SIGTERM обрабатываются для восстановления авто-режима кулеров
- SwiftUI Text с числами: использовать `Text(verbatim:)` чтобы избежать locale-форматирования
- XPC протокол — `@objc`, данные передаются как JSON-encoded Data (FanInfo/SensorInfo — Codable)
- NSAlert вместо SwiftUI .alert в MenuBarExtra (баг SwiftUI: .alert закрывает popover)
- **UserDefaults-суита `com.blik.shared`** — общее хранилище между BlikApp и BlikMenuBar (разные исполняемые файлы, `.standard` не разделяется): кастомные имена метрик (`MetricNameStore`, ключ `metricCustomNames.v1`) и конфиг виджетов графиков (`ChartWidgetStore`, ключ `chartWidgets.v1`)

## Локальная история и графики

- **История (BlikCore/History + BlikHelper/HistoryRecorder):** daemon пишет метрики в SQLite `/Library/Application Support/Blik/history.db` каждые 5 с, пока открыт любой клиент (BlikApp/BlikMenuBar/CLI). Две serial-очереди (sampling / db) — чтения графиков никогда не ждут SMC. Ретенция: raw 24 ч, 1-мин роллапы 7 дней. Все чтения — только через XPC (`queryHistory`/`listHistoryMetrics`); root-owned WAL-БД нечитаема из user-процессов напрямую.
- **XPC-версионирование:** range-режим графиков гейтится `BlikRuntime.helperSupportsHistory` (`Constants.minHelperVersionForHistory` vs `XPCConstants.helperVersion`); старый daemon → empty-state, не зависание.
- **Вкладка «Графики» (`SidebarTab.charts`, `Sources/BlikApp/Views/Charts/`):** фиксированный набор виджетов-зеркал веб-«Избранного» (Swift Charts), по умолчанию live-поллинг, период не дальше 7 дней. Виджеты редактируются (метрики/пороги), не добавляются/удаляются.
- **Переименование метрик (инлайн):** `EditableMetricLabel` на вкладках Температура/Ресурсы — hover → клик → поле → автосейв при потере фокуса, пусто = сброс к дефолту. Имена применяются в menubar-popup и легендах графиков (`MetricNameStore`).

## Управление кулерами на M4 — критические особенности
- **Ftst=1** — обязательный unlock от thermalmonitord перед ручным управлением
- После Ftst=1 нужна пауза ~5с, пока F{n}Md перейдёт из 3 (system) → 0 (auto)
- Затем **F{n}Md=1** — включение forced mode (с retry до 5 попыток)
- Только после этого **F{n}Tg** (target speed) реально применяется
- `writeKey()` **обязательно** вызывает `readKeyInfo()` для получения `dataAttributes` — без этого SMC молча игнорирует запись
- При выходе/восстановлении auto: F{n}Md=0 для всех кулеров → Ftst=0
- При запуске — безусловный сброс всех кулеров в auto (защита от «осиротевшего» состояния)
- Daemon сам делает reinforceSpeed() каждую секунду для кулеров в manual режиме

## Управление скоростью — пресеты
Скорость всегда меняется для всех кулеров одновременно. Пресеты: 0% (авто), 25%, 50%, 75%, 100%.
RPM рассчитывается как `min + (max - min) * percentage / 100` для каждого кулера.
0% = авто-режим (RPM=0, F{n}Md=0, Ftst=0).

### CLI (горячие клавиши)
- `1` — 0% (Авто) — вернуть все кулеры в авто-режим
- `2` — 25% скорости
- `3` — 50% скорости
- `4` — 75% скорости
- `5` — 100% скорости
- `↑/↓` — скролл плитки «Остальные сенсоры»
- `Q` — выход с восстановлением авто-режима

### MenuBar
- 5 кнопок-пресетов (Авто, 25%, 50%, 75%, 100%) под прогресс-барами кулеров
- Активный пресет подсвечивается
- Баннер "Доступно обновление" с кнопкой "Обновить" (`.borderedProminent`, автообновление через daemon)
- Кнопка "Настройки" в footer'е popup'а — открывает GUI BlikApp на экране настроек через `blik://settings` URL scheme

## UX паттерны
- При переключении из авто в ручной режим — UI обновляется мгновенно (плашки MANUAL, пресет), не дожидаясь завершения разблокировки SMC
- Во время разблокировки показывается уведомление "Разблокировка управления..."
- Для writer передаются оригинальные (до мутации state) данные fans, чтобы `isForced` проверка в `setAllFansSpeed` была корректной

## Автообновление
- Daemon проверяет GitHub Releases API (`squaretus/blik`) при старте (10с задержка) + каждые 6 часов
- Результат кэшируется в памяти daemon; `checkForUpdate` возвращает кэш, `checkForUpdateForced` — свежий запрос на GitHub
- MenuBar и CLI `--update` используют forced-проверку — всегда актуальные данные
- MenuBar: баннер `UpdateBannerView` с кнопкой "Обновить" → `performUpdate` через XPC
- CLI: жёлтая строка "Доступно обновление. Перейдите в выпадающее окно строки меню" над тайлом "Управление"
- Установка: daemon скачивает PKG в `/tmp/blik-update.pkg` → `installer -pkg ... -target /` (silent)
- Самоперезапуск: `installer` запускает `preinstall` (bootout) → `postinstall` (bootstrap) — новые бинарники
- Модели: `SemanticVersion` (Comparable), `UpdateInfo` (Codable) в BlikCore
- `UpdateChecker` (caseless enum) в BlikHelper — GitHub API, скачивание, установка

## Логирование
- CLI: лог пишется в `blik.log` в рабочей директории, очистка: `> blik.log`
- MenuBar: логи через `os.Logger` (subsystem: `com.blik.menubar`)
- Helper daemon: `HelperLogger` — пишет одновременно в NSLog (syslog) и в файл `/Library/Logs/Blik/helper.log`
  - Просмотр: `cat /Library/Logs/Blik/helper.log`
  - Ротация: при 1 МБ старый → `helper.log.old`
  - syslog: `log stream --predicate 'process == "BlikHelper"' --info`

## Установка и удаление
- Сборка: `scripts/build.sh 1.2.0` → `.build/release_build/Blik-1.2.0.pkg`
- Установка: PKG-визард, ставит app + daemon + CLI + автозапуск
- Удаление: кнопка в app, перетаскивание в корзину (daemon самоочистка), или `bash /tmp/uninstall-helper.sh`


## Соглашение по веткам и коммитам

- `feature/<имя>` — новые фичи, любая новая разработка
- `fix/<имя>` — исправления, рефакторинги, чистка

**Коммит-сообщение строго равно имени ветки.** Без описаний, тел, эмодзи, AI-меток. Все коммиты ветки имеют одинаковое сообщение; squash-merge при PR объединяет их в одну запись. Правило переопределяет глобальный формат `{номер задачи} - {Название}` из `~/.claude/CLAUDE.md`.
