---
description: Настроить вывод метрик blik (температуры, RAM/VRAM со спарклайнами) в статус-бар Claude Code
disable-model-invocation: true
---

Настрой вывод метрик blik в статус-бар Claude Code пользователя.

1. Проверь, что blik установлен: существует исполняемый `/usr/local/bin/blik` и `blik claude-statusline` выводит строку метрик. Если blik не установлен — остановись и сообщи, что сначала нужно установить PKG из https://github.com/squaretus/blik/releases/latest.
2. Прочитай `~/.claude/settings.json` (если файла нет — создай).
3. Если `statusLine` НЕ настроен — добавь:

```json
"statusLine": {
  "type": "command",
  "command": "/usr/local/bin/blik claude-statusline",
  "refreshInterval": 5
}
```

4. Если `statusLine` уже настроен на пользовательский скрипт — НЕ заменяй его. Вместо этого добавь в конец скрипта вызов `blik claude-statusline` отдельной последней строкой (метрики принято показывать под остальной информацией), например для bash-скрипта:

```bash
if [ -x /usr/local/bin/blik ]; then
  blik_line=$(/usr/local/bin/blik claude-statusline 2>/dev/null)
  [ -n "$blik_line" ] && printf '\n%s' "$blik_line"
fi
```

И убедись, что в конфиге `statusLine` есть `"refreshInterval": 5`.

5. Сообщи пользователю, что статус-бар обновится в течение нескольких секунд; если строки метрик нет — нужно проверить, что daemon blik запущен (открыть приложение Blik).
