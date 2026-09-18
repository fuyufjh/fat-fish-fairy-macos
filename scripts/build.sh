#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
APP="$ROOT/dist/FatFishFairy.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FatFishFairy "$APP/Contents/MacOS/FatFishFairy"
swift scripts/make-icon.swift .build/FatFish.iconset
iconutil -c icns .build/FatFish.iconset -o "$APP/Contents/Resources/FatFish.icns"
APP_PATH="$APP" PROJECT_PATH="$ROOT" /usr/bin/python3 - <<'PY'
import os, plistlib
info = {
    'CFBundleName': 'FatFishFairy', 'CFBundleDisplayName': '小肥鱼',
    'CFBundleIdentifier': 'com.fatfishfairy.macos', 'CFBundleExecutable': 'FatFishFairy',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.0.0',
    'CFBundleIconFile': 'FatFish',
    'CFBundleVersion': '1', 'LSMinimumSystemVersion': '14.0',
    'NSHighResolutionCapable': True,
    'NSScreenCaptureUsageDescription': '小肥鱼需要查看屏幕，并将截图发送给 DeepSeek 来陪你聊天。',
    'FatFishProjectDirectory': os.environ['PROJECT_PATH'],
    'NSHumanReadableCopyright': 'FatFishFairy macOS · Inspired by vczh/FatFishFairy',
}
with open(os.environ['APP_PATH'] + '/Contents/Info.plist', 'wb') as f:
    plistlib.dump(info, f)
PY
codesign --force --deep --sign - --identifier com.fatfishfairy.macos "$APP"
echo "Built: $APP"
