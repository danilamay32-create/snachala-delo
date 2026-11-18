#!/bin/bash
# CI: установить pkg, прогнать тест службы, снять скриншоты окна, удалить.
set -uo pipefail
cd "$(dirname "$0")/.."
PKG=$(ls build/*.pkg | head -1)
installer -pkg "$PKG" -target / || exit 1
sleep 5
launchctl print system/ru.snachaladelo.daemon | head -20
# Пустышка с bundle id VLC, собранная от обычного пользователя.
BUILDER="${SUDO_USER:-$(stat -f %Su /dev/console)}"
FAKE="$PWD/build/FakeVLC.app"
rm -rf "$FAKE"
sudo -u "$BUILDER" mkdir -p "$FAKE/Contents/MacOS"
printf '#include <unistd.h>\nint main(void){ sleep(300); return 0; }\n' > /tmp/fakevlc.c
sudo -u "$BUILDER" cc -o "$FAKE/Contents/MacOS/FakeVLC" /tmp/fakevlc.c
cat > "$FAKE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.videolan.vlc</string>
<key>CFBundleExecutable</key><string>FakeVLC</string></dict></plist>
PLIST
codesign --force --sign - "$FAKE"

FAKE_APP="$FAKE" python3 scripts/e2e.py; RC=$?

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
echo "DNS после удаления:"; networksetup -listallnetworkservices | tail -n +2 | grep -v '^\*' | while read -r svc; do echo "  $svc: $(networksetup -getdnsservers "$svc" | tr '\n' ' ')"; done
if networksetup -listallnetworkservices | tail -n +2 | grep -v '^\*' | while read -r svc; do networksetup -getdnsservers "$svc"; done | grep -q '^127\.0\.0\.1$'; then echo "FAIL uninstall оставил DNS 127.0.0.1"; RC=1; else echo "PASS uninstall вернул DNS"; fi
# Всё, что тест создал под root, вернуть пользователю.
chown -R "$BUILDER" build
if grep -q "Сначала дело" /private/etc/hosts; then echo "FAIL uninstall оставил hosts"; RC=1; else echo "PASS uninstall"; fi
exit $RC
