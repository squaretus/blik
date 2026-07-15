# blik

Мониторинг системы и управление вентиляторами для Mac на Apple Silicon (macOS 26+, протестировано на M4): GUI-приложение, MenuBar-приложение, CLI (TUI / MCP / statusline) и привилегированный XPC-daemon. Swift 5.9+, SwiftUI, Swift Package Manager. Приложение полностью бесплатное, без сервера и телеметрии.

## Запуск

```bash
swift build                    # Debug-сборка всех targets
swift test                     # Тесты
scripts/build.sh 1.2.0         # PKG-установщик → .build/release_build/Blik-1.2.0.pkg
sudo .build/debug/blik         # CLI напрямую через SMC (без установленного daemon'а)
blik                           # CLI TUI через XPC (после установки PKG, без sudo)
```

## Документация

- Карта проекта (стек, команды, структура, индекс модулей): `.claude/rules/ARCHITECTURE.md`
- Операционная память (modules / features / bugs / decisions / runbooks): `.claude/docs/`

@.claude/rules/ARCHITECTURE.md

## Соглашения

- Ветки: `feature/<имя>` — новая разработка, `fix/<имя>` — исправления/чистка. **Коммит-сообщение строго равно имени ветки** — без описаний, тел, эмодзи, AI-меток; squash-merge при PR объединяет коммиты в одну запись. Правило переопределяет глобальный формат `{номер задачи} - {Название}`.
- Файл с `@main` называется по имени приложения (`Blik.swift`, `BlikMenuBarApp.swift`, `BlikAppMain.swift`), не `main.swift` — конфликт с `@main`. Исключение: `BlikHelper/main.swift` (без `@main`, используется `dispatchMain()`).
- Sleep/wake: polling-Task'и VM отменяются/перезапускаются через `addObserver` на `NSWorkspace.willSleepNotification`/`didWakeNotification` со stored token — НЕ через async sequence (`Notification` не Sendable под Swift 6).
- NSAlert вместо SwiftUI `.alert` в MenuBarExtra (баг SwiftUI: `.alert` закрывает popover).
- Интеграция с Claude Code: сабкоманды `blik claude-statusline` (ANSI-строка метрик) и `blik mcp` (stdio-сервер, 4 инструмента). Репозиторий — маркетплейс плагинов Claude Code: `.claude-plugin/marketplace.json` + `plugins/blik/`; установка — `/plugin marketplace add squaretus/blik` → `/plugin install blik@blik`.
