#!/bin/bash
# TestFlight용 서명된 IPA. 업로드는 Transporter에 드래그.
set -euo pipefail
cd "$(dirname "$0")/.."

YML="project.yml"
OLD_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' "$YML" | head -1 | grep -o '[0-9]\+')
BUILD=$((OLD_BUILD + 1))
if [[ "$OSTYPE" == darwin* ]]; then
  sed -i '' -E "s/(CURRENT_PROJECT_VERSION:[[:space:]]*)\"?[0-9]+\"?/\1\"${BUILD}\"/" "$YML"
else
  sed -i -E "s/(CURRENT_PROJECT_VERSION:[[:space:]]*)\"?[0-9]+\"?/\1\"${BUILD}\"/" "$YML"
fi

WORK=$(mktemp -d)
OUT="$(pwd)/Health-build${BUILD}.ipa"
echo "▶ 빌드 번호 ${OLD_BUILD} → ${BUILD}"
xcodegen generate --quiet
xcodebuild -project Health.xcodeproj -scheme Health \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$WORK/Health.xcarchive" -allowProvisioningUpdates \
  archive > "$WORK/archive.log" 2>&1 \
  || { echo "✗ 아카이브 실패 — $WORK/archive.log"; grep -m5 "error:" "$WORK/archive.log" || true; exit 1; }

cat > "$WORK/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>28829JTDUM</string>
    <key>destination</key><string>export</string>
    <key>uploadSymbols</key><true/>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$WORK/Health.xcarchive" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$WORK/export" -allowProvisioningUpdates > "$WORK/export.log" 2>&1 \
  || { echo "✗ 추출 실패 — $WORK/export.log"; grep -m5 "error:" "$WORK/export.log" || true; exit 1; }

IPA_SRC=$(find "$WORK/export" -name '*.ipa' | head -1)
cp "$IPA_SRC" "$OUT"
echo "▶ IPA: $OUT"
echo "Transporter에 드래그하세요. 번들 ID: com.wooram.health"
