#!/bin/bash
# Собирает NotchClaude.app (агент без иконки в Dock) в build/.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/NotchClaude.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/NotchClaude "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>NotchClaude</string>
  <key>CFBundleIdentifier</key><string>dev.airshow.notchclaude</string>
  <key>CFBundleName</key><string>NotchClaude</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "готово: $APP  (запуск: open $APP)"
