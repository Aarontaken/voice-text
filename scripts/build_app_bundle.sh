#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
MANUAL_BUILD_DIR="$ROOT_DIR/.build/manual-release"
APP_DIR="$ROOT_DIR/build/VoiceText.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

if swift build -c release --product VoiceTextApp; then
  EXECUTABLE="$BUILD_DIR/VoiceTextApp"
else
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
  mkdir -p "$MANUAL_BUILD_DIR"
  swiftc -O -emit-library -emit-module \
    -module-name VoiceTextCore \
    -sdk "$SDK_PATH" \
    "$ROOT_DIR"/Sources/VoiceTextCore/*.swift \
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

codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
