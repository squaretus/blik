#!/bin/bash
echo "Полное удаление .blik..."

# Завершить приложения (если запущены)
killall .blikApp 2>/dev/null
killall .blikMenuBar 2>/dev/null
sleep 1

# Остановить daemon и agent
sudo launchctl bootout system/com.blik.helper 2>/dev/null
CURRENT_UID=$(id -u "$USER")
launchctl bootout gui/"$CURRENT_UID"/com.blik.app 2>/dev/null

# Удалить бинарники и plists
sudo rm -f /Library/PrivilegedHelperTools/com.blik.helper
sudo rm -f /Library/LaunchDaemons/com.blik.helper.plist
sudo rm -f /Library/LaunchAgents/com.blik.app.plist
sudo rm -f /usr/local/bin/blik
sudo rm -rf /Applications/Blik.app
sudo rm -rf "/Applications/.blik Panel.app"

# Удалить лицензию (только при полном удалении, не при обновлении)
sudo rm -rf "/Library/Application Support/blik"

# Удалить логи, preferences, кэши
rm -rf ~/Library/Logs/.blik
rm -f ~/Library/Preferences/com.blik.*
rm -rf ~/Library/Caches/com.blik.*

# Сбросить TCC-разрешения
tccutil reset All com.blik.app 2>/dev/null

# Удалить PKG receipt
sudo pkgutil --forget com.blik.pkg 2>/dev/null

echo ".blik полностью удалён."
