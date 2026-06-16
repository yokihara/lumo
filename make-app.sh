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

# Developer ID 서명: DEV_ID_APP 환경변수가 있으면 hardened runtime으로 정식 서명,
# 없으면 ad-hoc 서명 (로컬/지인 배포용 — 첫 실행 시 우클릭→열기 필요)
if [ -n "${DEV_ID_APP:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$DEV_ID_APP" "$APP"
else
    codesign --force --sign - "$APP"
fi

echo "built $APP"
