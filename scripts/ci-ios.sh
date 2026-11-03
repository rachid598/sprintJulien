#!/usr/bin/env bash
# Compile/test with the selected Xcode. Produces an unsigned device archive.
set -euo pipefail
cd "$(dirname "$0")/.."
artifact_dir="${ARTIFACT_DIR:-.build-ci}"
mkdir -p "$artifact_dir"
xcodebuild -version

simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
candidates = [d for runtime, items in devices.items() if "iOS" in runtime
              for d in items if d.get("isAvailable") and "iPhone" in d["name"]]
if not candidates:
    raise SystemExit("Aucun simulateur iPhone disponible dans Xcode")
candidates.sort(key=lambda d: (d.get("state") != "Booted", d["name"]))
print(candidates[0]["udid"])
')"
destination="platform=iOS Simulator,id=$simulator_id"

xcodebuild -project SprintTimer.xcodeproj -scheme SprintTimer \
  -configuration Debug -destination "$destination" \
  -derivedDataPath "$artifact_dir/DerivedData" \
  -resultBundlePath "$artifact_dir/TestResults.xcresult" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$artifact_dir/test.log"

xcodebuild -project SprintTimer.xcodeproj -scheme SprintTimer \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$artifact_dir/DerivedData" \
  -archivePath "$artifact_dir/SprintTimer.xcarchive" \
  CODE_SIGNING_ALLOWED=NO archive 2>&1 | tee "$artifact_dir/archive.log"

ditto -c -k --keepParent "$artifact_dir/SprintTimer.xcarchive" \
  "$artifact_dir/SprintTimer-unsigned.xcarchive.zip"
printf '%s\n' "Tests et archive terminés. Archive non signée : $artifact_dir/SprintTimer-unsigned.xcarchive.zip"
