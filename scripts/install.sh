#!/usr/bin/env bash
# Build this fork and install it over /Applications/Notchi.app.
#
# The fork keeps the upstream bundle identifier so it reuses the same
# preferences, hooks and Claude Code socket. Only one of the two can run, so
# this replaces the installed copy rather than living beside it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$REPO_ROOT/notchi/notchi.xcodeproj"
SCHEME="notchi"
DERIVED_DATA_PATH="$REPO_ROOT/build/install"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/notchi.app"
INSTALL_PATH="/Applications/Notchi.app"

echo "==> Building Release"
xcodebuild build \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination "platform=macOS" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGN_IDENTITY=- \
    ENABLE_HARDENED_RUNTIME=NO \
    > "$REPO_ROOT/build/install.log" 2>&1

if [[ ! -d "$BUILT_APP" ]]; then
    echo "Build produced no app. See $REPO_ROOT/build/install.log" >&2
    exit 1
fi

echo "==> Quitting running instance"
osascript -e 'quit app "Notchi"' 2>/dev/null || true
sleep 1
pkill -x notchi 2>/dev/null || true

echo "==> Installing to $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP" "$INSTALL_PATH"

echo "==> Launching"
open "$INSTALL_PATH"

echo "Done. Enable Launch at Login from the notch panel settings if it is not already on."
