#!/bin/sh
# Build a distributable DMG. For Developer ID signing + notarization:
#   1) one time: xcrun notarytool store-credentials lumo-notary \
#        --apple-id <apple-id-email> --team-id <team-id> --password <app-password>
#      (create an app password at appleid.apple.com -> Sign-In and Security -> App-Specific Passwords)
#   2) DEV_ID_APP="Developer ID Application: NAME (TEAMID)" ./release.sh
# Without DEV_ID_APP it produces an ad-hoc signed DMG (for personal sharing).
set -e
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
DMG="dist/Lumo-$VERSION.dmg"

./make-app.sh

STAGING=$(mktemp -d)
cp -R dist/Lumo.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Lumo" -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"
echo "created $DMG"

if [ -n "${DEV_ID_APP:-}" ]; then
    codesign --force --timestamp --sign "$DEV_ID_APP" "$DMG"
    echo "notarizing (takes a few minutes)..."
    xcrun notarytool submit "$DMG" --keychain-profile lumo-notary --wait
    xcrun stapler staple "$DMG"
    echo "notarized: $DMG — installs anywhere without a warning now"
else
    echo "ad-hoc build: recipient must right-click -> Open on first launch"
fi
