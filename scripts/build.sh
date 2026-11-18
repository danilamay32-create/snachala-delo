#!/bin/bash
# Собирает «Сначала дело.app» (Intel + Apple Silicon) и установщик build/SnachalaDelo.pkg.
# Нужны только Command Line Tools: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
APP_NAME="Сначала дело.app"
OUT=build
rm -rf "$OUT"; mkdir -p "$OUT"

for arch in arm64 x86_64; do
  echo "==> swift build ($arch)"
  swift build -c release --triple "$arch-apple-macosx12.0" --scratch-path ".build/$arch"
done

bin() { echo "$(swift build -c release --triple "$1-apple-macosx12.0" --scratch-path ".build/$1" --show-bin-path)/$2"; }
ROOT="$OUT/root"
APP="$ROOT/Applications/$APP_NAME"
mkdir -p "$APP/Contents/MacOS" "$ROOT/Library/PrivilegedHelperTools" \
         "$ROOT/Library/LaunchDaemons" "$ROOT/Library/LaunchAgents"

lipo -create "$(bin arm64 SnachalaDelo)" "$(bin x86_64 SnachalaDelo)" -output "$APP/Contents/MacOS/SnachalaDelo"
lipo -create "$(bin arm64 SnachalaDeloDaemon)" "$(bin x86_64 SnachalaDeloDaemon)" \
     -output "$ROOT/Library/PrivilegedHelperTools/ru.snachaladelo.daemon"
sed "s/__VERSION__/$VERSION/g" Support/Info.plist > "$APP/Contents/Info.plist"
cp Support/ru.snachaladelo.daemon.plist "$ROOT/Library/LaunchDaemons/"
cp Support/ru.snachaladelo.app.plist "$ROOT/Library/LaunchAgents/"

echo "==> codesign (ad-hoc)"
codesign --force --sign - --identifier ru.snachaladelo.daemon "$ROOT/Library/PrivilegedHelperTools/ru.snachaladelo.daemon"
codesign --force --sign - "$APP"

echo "==> pkg"
chmod +x scripts/postinstall scripts/preinstall
SCRIPTS="$OUT/scripts"; mkdir -p "$SCRIPTS"
cp scripts/postinstall scripts/preinstall "$SCRIPTS/"
pkgbuild --analyze --root "$ROOT" "$OUT/components.plist" >/dev/null
# Не давать установщику «перемещать» приложение в другую папку.
plutil -replace 0.BundleIsRelocatable -bool NO "$OUT/components.plist"
pkgbuild --root "$ROOT" --component-plist "$OUT/components.plist" --scripts "$SCRIPTS" \
  --identifier ru.snachaladelo.pkg --version "$VERSION" --install-location / \
  "$OUT/SnachalaDelo-$VERSION.pkg"
cp scripts/uninstall.sh "$OUT/"
echo "Готово: $OUT/SnachalaDelo-$VERSION.pkg"
