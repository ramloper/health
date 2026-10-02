#!/usr/bin/env bash
# Records HealthTests/Fixtures/progression-golden-v1.json from the current engines.
# Usage: ./scripts/record-golden.sh [force]   (force overwrites an existing fixture)
set -euo pipefail

cd "$(dirname "$0")/.."

GUARDED=(Health/Engines Health/Catalog Health/Resources/Programs)
if ! git diff --quiet main -- "${GUARDED[@]}"; then
    echo "error: engine/catalog/program files differ from main; golden must capture main's behaviour:" >&2
    git diff --name-only main -- "${GUARDED[@]}" >&2
    exit 1
fi

xcodegen generate --quiet

FIXTURE="HealthTests/Fixtures/progression-golden-v1.json"

TEST_RUNNER_RECORD_GOLDEN="${1:-1}" \
TEST_RUNNER_GOLDEN_COMMIT="$(git rev-parse HEAD)" \
xcodebuild test \
    -project Health.xcodeproj \
    -scheme Health \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath build/dd-golden \
    -only-testing:HealthTests/GoldenProgressionTests/testRecordGolden

if [[ ! -f "$FIXTURE" ]]; then
    echo "error: $FIXTURE was not written" >&2
    exit 1
fi
python3 -m json.tool "$FIXTURE" > /dev/null
echo "golden fixture: $(pwd)/$FIXTURE ($(wc -l < "$FIXTURE" | tr -d ' ') lines)"
