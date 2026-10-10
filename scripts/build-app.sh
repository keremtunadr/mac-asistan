#!/usr/bin/env bash
# Mac Asistan'ı derler, .app paketini oluşturur ve .dmg kurulum dosyası üretir.
# Kullanım: ./scripts/build-app.sh   (macOS + Xcode komut satırı araçları gerekir)
#
# İsteğe bağlı ortam değişkenleri:
#   VERSION        (varsayılan 0.1.0)
#   BUILD_NUMBER   (varsayılan 1)
#   SIGN_IDENTITY  Developer ID sertifikası adı; yoksa ad-hoc imza kullanılır
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_NAME="Mac Asistan"
EXECUTABLE="MacAsistan"
OUT="dist"
APP="$OUT/$APP_NAME.app"
DMG="$OUT/MacAsistan.dmg"

echo "==> Temizleniyor"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Derleniyor (universal: arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
if [ ! -f "$BIN_DIR/$EXECUTABLE" ]; then
  BIN_DIR=".build/apple/Products/Release"
fi
lipo -info "$BIN_DIR/$EXECUTABLE"

echo "==> .app paketi oluşturuluyor"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp -R Resources/Localizations/*.lproj "$APP/Contents/Resources/"
printf "APPL????" > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"

echo "==> Simge oluşturuluyor"
if swift scripts/make-icon.swift "$OUT/AppIcon.iconset" && iconutil -c icns "$OUT/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"; then
  echo "Simge hazır"
else
  echo "UYARI: simge oluşturulamadı, varsayılan simge kullanılacak"
fi
rm -rf "$OUT/AppIcon.iconset"

echo "==> İmzalanıyor"
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp \
    --entitlements Resources/MacAsistan.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - --entitlements Resources/MacAsistan.entitlements "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

echo "==> DMG oluşturuluyor"
STAGE="$OUT/dmg-root"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

echo "==> Bitti: $DMG"
ls -lh "$DMG"
