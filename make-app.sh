#!/bin/sh
set -e
cd "$(dirname "$0")"

swift build -c release

APP=dist/Lumo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Lumo "$APP/Contents/MacOS/Lumo"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Developer ID signing: if DEV_ID_APP is set, sign properly with the hardened runtime;
# otherwise ad-hoc sign (local/personal sharing — requires right-click → Open on first launch).
if [ -n "${DEV_ID_APP:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$DEV_ID_APP" "$APP"
else
    codesign --force --sign - "$APP"
fi

echo "built $APP"
