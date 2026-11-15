#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
MANUAL_BUILD_DIR="$ROOT_DIR/.build/manual-release"
APP_DIR="$ROOT_DIR/build/VoiceText.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

# Core 源码按目录组织（ASR/ 等子目录），手动编译回退路径也必须递归收集。
CORE_SOURCES=()
while IFS= read -r -d '' source_file; do
  CORE_SOURCES+=("$source_file")
done < <(find "$ROOT_DIR/Sources/VoiceTextCore" -name '*.swift' -print0)

if swift build -c release --product VoiceTextApp; then
  EXECUTABLE="$BUILD_DIR/VoiceTextApp"
else
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
  mkdir -p "$MANUAL_BUILD_DIR"
  swiftc -O -emit-library -emit-module \
    -module-name VoiceTextCore \
    -sdk "$SDK_PATH" \
    "${CORE_SOURCES[@]}" \
    -emit-module-path "$MANUAL_BUILD_DIR/VoiceTextCore.swiftmodule" \
    -Xlinker -install_name \
    -Xlinker @rpath/libVoiceTextCore.dylib \
    -o "$MANUAL_BUILD_DIR/libVoiceTextCore.dylib"
  swiftc -O \
    -sdk "$SDK_PATH" \
    -I "$MANUAL_BUILD_DIR" \
    -L "$MANUAL_BUILD_DIR" \
    -lVoiceTextCore \
    -Xlinker -rpath \
    -Xlinker @executable_path \
    "$ROOT_DIR"/Sources/VoiceTextApp/*.swift \
    -o "$MANUAL_BUILD_DIR/VoiceTextApp"
  EXECUTABLE="$MANUAL_BUILD_DIR/VoiceTextApp"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$EXECUTABLE" "$MACOS_DIR/VoiceTextApp"
if [ -f "$MANUAL_BUILD_DIR/libVoiceTextCore.dylib" ]; then
  cp "$MANUAL_BUILD_DIR/libVoiceTextCore.dylib" "$MACOS_DIR/libVoiceTextCore.dylib"
fi
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

RES_DIR="$CONTENTS_DIR/Resources"
mkdir -p "$RES_DIR"
ICON_SRC="$ROOT_DIR/Resources/VoiceText-AppIcon.png"
swift "$ROOT_DIR/scripts/render_app_icon.swift" "$ICON_SRC"
ICONSET_DIR="$ROOT_DIR/build/VoiceText.iconset"
ICNS_OUT="$RES_DIR/VoiceText.icns"
if [ ! -f "$ICON_SRC" ]; then
  echo "Missing app icon source: $ICON_SRC" >&2
  exit 1
fi
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUT"

# 用稳定的签名身份，避免每次重建后 TCC（辅助功能/麦克风）授权失效。
# 可通过 CODESIGN_IDENTITY 覆盖；CI 上没有证书时退回 ad-hoc。
SIGNING_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -Fq '"VoiceText Local Dev"'; then
    SIGNING_IDENTITY="VoiceText Local Dev"
  else
    SIGNING_IDENTITY="-"
  fi
fi
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"

echo "Signed with identity: $SIGNING_IDENTITY"
echo "Built $APP_DIR"
