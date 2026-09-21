#!/bin/bash
# Build the native app and, by default, a drag-to-install disk image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAKE_DMG=1
case "${1:-}" in
  "") ;;
  --app-only) MAKE_DMG=0 ;;
  -h|--help)
    echo "Usage: ./build.sh [--app-only]"
    echo "Default: build dist/FatFishFairy.app and dist/FatFishFairy-<version>-<arch>.dmg"
    echo "Optional environment: APP_VERSION=1.0.0"
    exit 0 ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then echo "Too many arguments. Use --help." >&2; exit 2; fi
if [ "$(uname -s)" != Darwin ]; then echo "Build this project on macOS." >&2; exit 1; fi
for tool in swift xcrun python3 codesign iconutil ditto hdiutil security openssl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing tool: $tool. Install Apple Command Line Tools: xcode-select --install" >&2
    exit 1
  fi
done
xcrun --find swift >/dev/null

APP_VERSION="${APP_VERSION:-1.0.0}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "APP_VERSION must have the form 1.0.0." >&2; exit 2
fi
# Pin the certificate, not its display name or a changing executable hash.
CERT="$ROOT/signing/FatFishFairy.cer"
if [ ! -f "$CERT" ]; then
  echo "Missing public signing certificate: $CERT" >&2; exit 1
fi
SIGN_IDENTITY="$(openssl x509 -inform DER -in "$CERT" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
if [[ ! "$SIGN_IDENTITY" =~ ^[A-F0-9]{40}$ ]]; then
  echo "Invalid signing certificate fingerprint." >&2; exit 1
fi
if [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "$CODE_SIGN_IDENTITY" != "$SIGN_IDENTITY" ]; then
  echo "CODE_SIGN_IDENTITY differs from the pinned certificate. Refusing to change the app identity." >&2; exit 1
fi
if ! security find-identity -p codesigning | grep -Fq "$SIGN_IDENTITY"; then
  echo "The pinned signing identity is missing from your keychains. Restore its certificate and private key; ad-hoc fallback is disabled." >&2; exit 1
fi
SIGN_REQUIREMENT="identifier \"com.fatfishfairy.macos\" and certificate leaf = H\"$SIGN_IDENTITY\""
ARCH="$(uname -m)"
DIST="$ROOT/dist"
mkdir -p "$DIST"
WORK="$(mktemp -d "$DIST/.fatfish-build.XXXXXX")"
cleanup() {
  local result=$?
  # Restore the previous app if publishing its replacement was interrupted.
  if [ -d "$WORK/previous.app" ] && [ ! -e "$DIST/FatFishFairy.app" ]; then
    mv "$WORK/previous.app" "$DIST/FatFishFairy.app"
  fi
  rm -rf "$WORK"
  trap - EXIT
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$ROOT"
echo "Building FatFishFairy $APP_VERSION ($ARCH)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$WORK/FatFishFairy.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FatFishFairy" "$APP/Contents/MacOS/FatFishFairy"
ditto "$ROOT/Sources/FatFishFairy/Resources/Themes" "$APP/Contents/Resources/Themes"
cp "$ROOT/Sources/FatFishFairy/Resources/SystemPrompt.md" "$APP/Contents/Resources/SystemPrompt.md"
cp "$ROOT/Sources/FatFishFairy/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
swift "$ROOT/scripts/make-icon.swift" "$WORK/FatFish.iconset" "$ROOT/Sources/FatFishFairy/Resources/AppIcon.png"
iconutil -c icns "$WORK/FatFish.iconset" -o "$APP/Contents/Resources/FatFish.icns"
APP_PATH="$APP" VERSION_VALUE="$APP_VERSION" python3 - <<'PY'
import os, plistlib
info = {
    'CFBundleName': 'FatFishFairy', 'CFBundleDisplayName': '小肥鱼',
    'CFBundleIdentifier': 'com.fatfishfairy.macos', 'CFBundleExecutable': 'FatFishFairy',
    'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': os.environ['VERSION_VALUE'],
    'CFBundleIconFile': 'FatFish', 'CFBundleVersion': '1',
    'LSMinimumSystemVersion': '14.0', 'NSHighResolutionCapable': True,
    'NSScreenCaptureUsageDescription': '小肥鱼需要查看屏幕，并将截图发送给你配置的 API 服务来陪你聊天。',
    'NSHumanReadableCopyright': 'FatFishFairy macOS · Inspired by vczh/FatFishFairy',
}
with open(os.environ['APP_PATH'] + '/Contents/Info.plist', 'wb') as output:
    plistlib.dump(info, output)
PY
# The bundle is assembled from an explicit allowlist; .secret is never copied.
codesign --force --sign "$SIGN_IDENTITY" --identifier com.fatfishfairy.macos --requirements "=designated => $SIGN_REQUIREMENT" "$APP"
codesign --verify --deep --strict -R "=$SIGN_REQUIREMENT" "$APP"

if [ "$MAKE_DMG" = 1 ]; then
  IMAGE_ROOT="$WORK/image"
  mkdir -p "$IMAGE_ROOT"
  ditto "$APP" "$IMAGE_ROOT/FatFishFairy.app"
  ln -s /Applications "$IMAGE_ROOT/Applications"
  cp "$ROOT/THIRD_PARTY_NOTICES.md" "$IMAGE_ROOT/THIRD_PARTY_NOTICES.md"
  cat > "$IMAGE_ROOT/安装说明.txt" <<'TEXT'
小肥鱼 · FatFishFairy

1. 将 FatFishFairy.app 拖到 Applications 文件夹，然后推出此磁盘映像。
2. 从「应用程序」打开小肥鱼。
3. 在设置的「模型连接」中填写 API Key 并保存。可修改 Base URL、Model 和高级思考选项；密钥随配置保存在本机。
4. 按提示授予小肥鱼屏幕录制权限，再开启自动观察。

需要 macOS 14 或更新版本。识图和对话默认使用 deepseek-flash，可在设置中修改。
已内置「蓝色小肥鱼」和「长大的妹抖」，可在「桌面形象」切换，无需另行下载或导入。
安装包不包含 API 密钥、聊天记录、记忆或导入的主题。
默认构建仅本机签名，未经过 Apple 公证。
TEXT
  DMG_NAME="FatFishFairy-$APP_VERSION-$ARCH.dmg"
  echo "Packaging ${DMG_NAME}…"
  hdiutil create -volname "FatFishFairy" -srcfolder "$IMAGE_ROOT" \
    -fs HFS+ -format UDZO -ov "$WORK/$DMG_NAME"
  hdiutil verify "$WORK/$DMG_NAME"
fi

# Publish only after building, signing, and packaging have all succeeded.
if [ -e "$DIST/FatFishFairy.app" ]; then mv "$DIST/FatFishFairy.app" "$WORK/previous.app"; fi
mv "$APP" "$DIST/FatFishFairy.app"
if [ "$MAKE_DMG" = 1 ]; then mv -f "$WORK/$DMG_NAME" "$DIST/$DMG_NAME"; fi
echo "App: $DIST/FatFishFairy.app"
if [ "$MAKE_DMG" = 1 ]; then echo "DMG: $DIST/$DMG_NAME"; fi
