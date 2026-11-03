#!/bin/sh
# Builds Release and installs it as /Applications/Simplify.app, the one copy macOS should list.
#
# The build goes to build/release.noindex: Spotlight skips folders ending in .noindex, and the
# copy is unregistered from Launch Services afterwards, so Launchpad, Spotlight and "Open With"
# show Simplify once, and the widget gallery shows one set of widgets.
#
# Usage: scripts/install.sh [--no-open]
set -eu

cd "$(dirname "$0")/.."
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DERIVED=build/release.noindex
BUILT="$DERIVED/Build/Products/Release/Simplify.app"
TARGET=/Applications/Simplify.app

xcodegen generate --quiet
xcodebuild -project Simplify.xcodeproj -scheme Simplify -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" -allowProvisioningUpdates -quiet build

# Unregister the build copy and its widget before anything can launch it.
"$LSREGISTER" -u "$BUILT/Contents/PlugIns/SimplifyWidgets.appex" 2>/dev/null || true
"$LSREGISTER" -u "$BUILT" 2>/dev/null || true

# Quit the running app so the new one replaces it cleanly.
if pgrep -xq Simplify; then
  osascript -e 'tell application id "dev.yoom.simplify" to quit' || true
  while pgrep -xq Simplify; do sleep 0.5; done
fi

rm -rf "$TARGET"
ditto "$BUILT" "$TARGET"
codesign --verify --deep --strict "$TARGET"
"$LSREGISTER" -f "$TARGET"
echo "Installed $TARGET"

if [ "${1:-}" != "--no-open" ]; then open "$TARGET"; fi
