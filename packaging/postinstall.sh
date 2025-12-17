#!/bin/bash
# This pkg postinstall moves the staged LaunchBar action to the current user's ~/Library
set -euo pipefail

BUNDLE_NAME="@BUNDLE_NAME@"
PKG_STAGE_ROOT="@PKG_STAGE_ROOT@"

SOURCE="$PKG_STAGE_ROOT/Library/Application Support/LaunchBar/Actions/$BUNDLE_NAME"
CONSOLE_USER=$(stat -f %Su /dev/console)
if [ "$CONSOLE_USER" = "root" ] && [ -n "${SUDO_USER:-}" ]; then
  CONSOLE_USER="$SUDO_USER"
fi
DEST="/Users/$CONSOLE_USER/Library/Application Support/LaunchBar/Actions"
mkdir -p "$DEST"
cp -Rp "$SOURCE" "$DEST/"
chown -R "$CONSOLE_USER" "$DEST/$BUNDLE_NAME"
rm -rf "$SOURCE"
exit 0
