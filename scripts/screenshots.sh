#!/bin/bash
# App Store 스크린샷 생성. 결과: build/screenshots/*.png (6.9" = iPhone 17 Pro Max, 1320x2868), 9장 (01-today ~ 09-picker)
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-iPhone 17 Pro Max}"
OUT="build/screenshots"
RESULT="build/screenshots.xcresult"
rm -rf "$OUT" "$RESULT"
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available | grep "$DEVICE (" | head -1 | grep -oE '[0-9A-F-]{36}')
[[ -n "$UDID" ]] || { echo "✗ 시뮬레이터 '$DEVICE' 없음"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --operatorName ""

xcodegen generate --quiet
xcodebuild test -project Health.xcodeproj -scheme Health \
  -destination "platform=iOS Simulator,id=$UDID" \
  -only-testing:HealthUITests -resultBundlePath "$RESULT" -quiet \
  || { echo "✗ UI 테스트 실패"; exit 1; }

xcrun simctl status_bar "$UDID" clear
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT" >/dev/null
# manifest.json이 사람이 읽을 이름(<name>_<n>_<uuid>.png)을 갖고 있다. 우리 스냅샷만 남긴다.
python3 - "$OUT" <<'PY'
import json, os, sys, shutil
out = sys.argv[1]
manifest = json.load(open(os.path.join(out, "manifest.json")))
keep = set()
for test in manifest:
    for a in test.get("attachments", []):
        human = a.get("suggestedHumanReadableName", "")
        exported = a.get("exportedFileName", "")
        if human[:2].isdigit() and human.endswith(".png"):
            name = human.split("_")[0] + ".png"
            shutil.move(os.path.join(out, exported), os.path.join(out, name))
            keep.add(name)
for f in os.listdir(out):
    if f not in keep:
        p = os.path.join(out, f)
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
PY
echo "▶ 스크린샷: $OUT"
ls "$OUT"
