#!/bin/sh
# Полное удаление «Сначала дело». Нужен пароль администратора:
#   sudo sh uninstall.sh
set -u
if [ "$(id -u)" != "0" ]; then echo "Запусти через sudo: sudo sh $0"; exit 1; fi
UID_NOW=$(stat -f %u /dev/console)
launchctl bootout "gui/$UID_NOW/ru.snachaladelo.app" 2>/dev/null
launchctl bootout system/ru.snachaladelo.daemon 2>/dev/null
pkill -x SnachalaDelo 2>/dev/null
/Library/PrivilegedHelperTools/ru.snachaladelo.daemon --cleanup 2>/dev/null
rm -f /Library/LaunchDaemons/ru.snachaladelo.daemon.plist \
      /Library/LaunchAgents/ru.snachaladelo.app.plist \
      /Library/PrivilegedHelperTools/ru.snachaladelo.daemon \
      /var/run/ru.snachaladelo.sock
rm -rf "/Applications/Сначала дело.app" "/Library/Application Support/SnachalaDelo"
pkgutil --forget ru.snachaladelo.pkg >/dev/null 2>&1
echo "Удалено."
