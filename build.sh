#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${WALLNAMIC_BUILD_DIR:-${WALLFLOW_BUILD_DIR:-$PROJECT_DIR/.build}}"
APP_DIR="${WALLNAMIC_APP_DIR:-${WALLFLOW_APP_DIR:-$PROJECT_DIR/dist/Wallnamic.app}}"

if [ "${WALLNAMIC_CHECK_LOCALIZATION:-${WALLFLOW_CHECK_LOCALIZATION:-1}}" != "0" ]; then
    python3 "$PROJECT_DIR/scripts/check_localization.py"
fi

swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release --product VideoWallpaper
swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release --product WallFlowPlayer
BIN_DIR="$(swift build --package-path "$PROJECT_DIR" --scratch-path "$BUILD_DIR" -c release --show-bin-path)"

# Sign away from synced folders, which can add Finder metadata during signing.
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wallnamic-build.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGED_APP="$STAGE_DIR/Wallnamic.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/VideoWallpaper" "$STAGED_APP/Contents/MacOS/VideoWallpaper"
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
fi
PLAYER_APP="$STAGED_APP/Contents/Library/LoginItems/WallFlowPlayer.app"
mkdir -p "$PLAYER_APP/Contents/MacOS" "$PLAYER_APP/Contents/Resources"
cp "$BIN_DIR/WallFlowPlayer" "$PLAYER_APP/Contents/MacOS/WallFlowPlayer"
cp "$PROJECT_DIR/Resources/PlayerInfo.plist" "$PLAYER_APP/Contents/Info.plist"
for VERSION_KEY in CFBundleShortVersionString CFBundleVersion; do
    VERSION_VALUE="$(/usr/libexec/PlistBuddy -c "Print :$VERSION_KEY" "$PROJECT_DIR/Resources/Info.plist")"
    /usr/libexec/PlistBuddy -c "Set :$VERSION_KEY $VERSION_VALUE" "$PLAYER_APP/Contents/Info.plist"
done
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$PLAYER_APP/Contents/Resources/AppIcon.icns"
fi
# Copy every localization table so adding a language never needs a build-script edit.
for LPROJ in "$PROJECT_DIR"/Resources/*.lproj; do
    [ -d "$LPROJ" ] || continue
    cp -R "$LPROJ" "$STAGED_APP/Contents/Resources/"
    cp -R "$LPROJ" "$PLAYER_APP/Contents/Resources/"
done
codesign --force --sign - "$PLAYER_APP"
codesign --verify --strict "$PLAYER_APP"
codesign --force --sign - "$STAGED_APP"
codesign --verify --deep --strict "$STAGED_APP"
mkdir -p "$(dirname "$APP_DIR")"
ditto --norsrc --noextattr "$STAGED_APP" "$APP_DIR"
printf 'App: %s\n' "$APP_DIR"
