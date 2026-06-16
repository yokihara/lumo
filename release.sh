#!/bin/sh
# DMG 배포판 생성. Developer ID 서명 + 공증까지 하려면:
#   1) 최초 1회: xcrun notarytool store-credentials lumo-notary \
#        --apple-id <애플ID이메일> --team-id <팀ID> --password <앱암호>
#      (앱 암호는 appleid.apple.com → 로그인 및 보안 → 앱 암호에서 생성)
#   2) DEV_ID_APP="Developer ID Application: 이름 (팀ID)" ./release.sh
# DEV_ID_APP 없이 실행하면 ad-hoc 서명 DMG가 나온다 (지인 배포용).
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
    echo "notarizing (수 분 소요)..."
    xcrun notarytool submit "$DMG" --keychain-profile lumo-notary --wait
    xcrun stapler staple "$DMG"
    echo "notarized: $DMG — 이제 어디서든 경고 없이 설치 가능"
else
    echo "ad-hoc 빌드: 받는 사람은 첫 실행 시 우클릭 → 열기 필요"
fi
