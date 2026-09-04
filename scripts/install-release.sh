#!/usr/bin/env bash
# Install the latest GitHub release of the fork without Xcode.
#
#   curl -fsSL https://raw.githubusercontent.com/elumixor/notchi/main/scripts/install-release.sh | bash
#
# Downloads Notchi.zip from the newest release, replaces /Applications/Notchi.app,
# clears the quarantine flag (the build is ad-hoc signed, not notarised) and
# launches it. Set NOTCHI_VERSION=v1.3.0 to pin a release.
set -euo pipefail

REPO="${NOTCHI_REPO:-elumixor/notchi}"
VERSION="${NOTCHI_VERSION:-latest}"
INSTALL_PATH="/Applications/Notchi.app"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ "$VERSION" == "latest" ]]; then
    URL="https://github.com/$REPO/releases/latest/download/Notchi.zip"
else
    URL="https://github.com/$REPO/releases/download/$VERSION/Notchi.zip"
fi

echo "==> Downloading $URL"
curl -fsSL --retry 3 -o "$WORK_DIR/Notchi.zip" "$URL"

echo "==> Unpacking"
ditto -x -k "$WORK_DIR/Notchi.zip" "$WORK_DIR"
test -d "$WORK_DIR/Notchi.app"

echo "==> Quitting running instance"
osascript -e 'quit app "Notchi"' 2>/dev/null || true
sleep 1
pkill -x notchi 2>/dev/null || true

echo "==> Installing to $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
cp -R "$WORK_DIR/Notchi.app" "$INSTALL_PATH"
xattr -dr com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true

# Keychain items left by the upstream build are bound to its signing identity
# and would raise a password dialog on every launch; the fork recreates them.
for account in cachedOAuthToken; do
    security delete-generic-password -s com.ruban.notchi -a "$account" >/dev/null 2>&1 || true
done

echo "==> Launching"
open "$INSTALL_PATH"

echo "Done. Turn on Launch at Login under Settings > General in the notch panel."
