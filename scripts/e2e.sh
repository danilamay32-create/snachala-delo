#!/bin/bash
# CI: установить pkg, прогнать тест службы, снять скриншоты окна, удалить.
set -uo pipefail
cd "$(dirname "$0")/.."
PKG=$(ls build/*.pkg | head -1)
installer -pkg "$PKG" -target / || exit 1
sleep 5
launchctl print system/ru.snachaladelo.daemon | head -20
python3 scripts/e2e.py; RC=$?

# Скриншоты интерфейса (не влияют на результат).
mkdir -p build/shots
U=$(stat -f %u /dev/console)
if [ "$U" != "0" ]; then
  APPBIN="/Applications/Сначала дело.app/Contents/MacOS/SnachalaDelo"
  pkill -x SnachalaDelo; sleep 1
  launchctl asuser "$U" sudo -u "#$U" "$APPBIN" --open-window >/dev/null 2>&1 &
  sleep 6
  screencapture -x build/shots/popover.png || true
  pkill -x SnachalaDelo; sleep 1
  launchctl asuser "$U" sudo -u "#$U" "$APPBIN" --open-settings >/dev/null 2>&1 &
  sleep 6
  screencapture -x build/shots/settings.png || true
  pkill -x SnachalaDelo
fi

sh build/uninstall.sh
if grep -q "Сначала дело" /private/etc/hosts; then echo "FAIL uninstall оставил hosts"; RC=1; else echo "PASS uninstall"; fi
exit $RC
