#!/bin/bash
set -euo pipefail
: "${UDID:?missing simulator UDID}"
mkdir -p out/picker
marker="/tmp/fotiq-picker-$UDID.home"
rm -f "$marker"
for label in clubs barcelona leagues cups; do rm -f "/tmp/fotiq-picker-$UDID-$label.png"; done
xcrun simctl uninstall "$UDID" ae.barq.football
app=$(find dd/Build/Products/Release-iphonesimulator -maxdepth 1 -name BARQ.app -print -quit)
test -d "$app"
xcrun simctl install "$UDID" "$app"
xcrun simctl io "$UDID" recordVideo --codec=h264 --force out/picker/Clubs-to-Home.mp4 >out/picker/recorder.log 2>&1 &
rec=$!
watcher=""
cleanup() {
  if [[ -n "$watcher" ]]; then kill "$watcher" 2>/dev/null || true; fi
  kill -INT "$rec" 2>/dev/null || true
  wait "$rec" || true
}
trap cleanup EXIT
for i in {1..60}; do
  kill -0 "$rec"
  if grep -q 'Recording started' out/picker/recorder.log; then break; fi
  sleep 1
done
grep -q 'Recording started' out/picker/recorder.log
(
  while kill -0 "$rec" 2>/dev/null; do
    if [[ -f "$marker" ]] && [[ "$(cat "$marker")" == "$UDID" ]]; then
      kill -INT "$rec"
      exit 0
    fi
    sleep 0.15
  done
) &
watcher=$!
xcodebuild -project BARQFootball.xcodeproj -scheme FOTIQUITests -destination "id=$UDID" -derivedDataPath dd -configuration Release -parallel-testing-enabled NO test-without-building -only-testing:BARQUITests/OnboardingUITests/testRecordedClubLeagueCupAndHome 2>&1 | tee out/picker/journey.log
test "$(cat "$marker")" = "$UDID"
wait "$watcher"
watcher=""
wait "$rec"
trap - EXIT
test -s out/picker/Clubs-to-Home.mp4
for label in clubs barcelona leagues cups; do
  shot="/tmp/fotiq-picker-$UDID-$label.png"
  test -s "$shot"
  cp "$shot" "out/picker/$label.png"
done
printf '%s\n' "$UDID" > out/picker/simulator-udid.txt
git rev-parse HEAD > out/picker/head.txt
container=$(xcrun simctl get_app_container "$UDID" ae.barq.football data)
python3 - "$container/Library/Preferences/ae.barq.football.plist" <<'PY'
import json, pathlib, plistlib, sys
d = plistlib.loads(pathlib.Path(sys.argv[1]).read_bytes())
clubs = [c["id"] for c in json.loads(d["favTeams"])]
competitions = json.loads(d["favLeagues"])
assert d["onboardingDone"] and clubs == [529] and set(competitions) == {140, 2}, (clubs, competitions)
result = {"onboardingDone": True, "clubIDs": clubs, "competitionIDs": competitions}
pathlib.Path("out/picker/selections.json").write_text(json.dumps(result))
print(result)
PY
