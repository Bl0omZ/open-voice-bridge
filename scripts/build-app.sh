#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="XiaomiRemoteBridgeMac"
DISPLAY_NAME="小米遥控器桥接"
OUTPUT_DIR="$ROOT/dist"
APP_DIR="$OUTPUT_DIR/$DISPLAY_NAME.app"

UNIVERSAL=0
PREVIEW=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --preview) PREVIEW=1 ;;
    *) print -u2 "unknown argument: $arg"; exit 1 ;;
  esac
done

if [[ "$PREVIEW" -eq 1 ]]; then
  DISPLAY_NAME="小米遥控器桥接-预览"
  APP_DIR="$OUTPUT_DIR/$DISPLAY_NAME.app"
fi

cd "$ROOT"

if [[ "$UNIVERSAL" -eq 1 ]]; then
  ARM64_SCRATCH="$ROOT/.build/universal-$CONFIGURATION-arm64"
  X86_64_SCRATCH="$ROOT/.build/universal-$CONFIGURATION-x86_64"
  xcrun swift build -c "$CONFIGURATION" --triple arm64-apple-macosx11.0 \
    --scratch-path "$ARM64_SCRATCH"
  ARM64_BIN_DIR="$(xcrun swift build -c "$CONFIGURATION" --triple arm64-apple-macosx11.0 \
    --scratch-path "$ARM64_SCRATCH" --show-bin-path)"
  xcrun swift build -c "$CONFIGURATION" --triple x86_64-apple-macosx11.0 \
    --scratch-path "$X86_64_SCRATCH"
  X86_64_BIN_DIR="$(xcrun swift build -c "$CONFIGURATION" --triple x86_64-apple-macosx11.0 \
    --scratch-path "$X86_64_SCRATCH" --show-bin-path)"

  UNIVERSAL_BIN="$ROOT/.build/universal-$CONFIGURATION/$APP_NAME"
  mkdir -p "${UNIVERSAL_BIN:h}"
  lipo -create -output "$UNIVERSAL_BIN" \
    "$ARM64_BIN_DIR/$APP_NAME" \
    "$X86_64_BIN_DIR/$APP_NAME"
  BIN_PATH="$UNIVERSAL_BIN"
else
  xcrun swift build -c "$CONFIGURATION"
  BIN_PATH="$(xcrun swift build -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"
fi

case "$APP_DIR" in
  "$ROOT/dist/"*.app) ;;
  *) print -u2 "refusing to clean unexpected app path: $APP_DIR"; exit 1 ;;
esac
rm -rf -- "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
ditto --norsrc --noextattr --noqtn --noacl \
  "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
strip -S -x "$APP_DIR/Contents/MacOS/$APP_NAME"
ditto --norsrc --noextattr --noqtn --noacl \
  "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
ditto --norsrc --noextattr --noqtn --noacl \
  "$ROOT/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
ditto --norsrc --noextattr --noqtn --noacl \
  "$ROOT/README.md" "$APP_DIR/Contents/Resources/README.md"
ditto --norsrc --noextattr --noqtn --noacl \
  "$ROOT/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
ditto --norsrc --noextattr --noqtn --noacl \
  "$ROOT/COPYRIGHT" "$APP_DIR/Contents/Resources/COPYRIGHT"
ditto --norsrc --noextattr --noqtn --noacl \
  "$ROOT/Resources/RC003-remote-photo.png" \
  "$APP_DIR/Contents/Resources/RC003-remote-photo.png"
ditto --norsrc --noextattr --noqtn --noacl \
  "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

if [[ "$PREVIEW" -eq 1 ]]; then
  INFO_PLIST="$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c \
    "Set :CFBundleIdentifier com.kingwell.XiaomiRemoteBridgeMac.preview" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Add :LSEnvironment:OVB_SHOW_SETTINGS string 1" "$INFO_PLIST"
fi

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

print "$APP_DIR"
