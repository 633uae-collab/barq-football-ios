#!/bin/bash
set -euo pipefail
MODE=${1:?first or quick}
[[ "$MODE" == first || "$MODE" == quick ]]
mkdir -p out
APP=$(find dd/Build/Products -name BARQ.app -path '*iphonesimulator*' | head -1)
xcrun simctl install "$UDID" "$APP"
if [[ "$MODE" == first ]]; then
  xcrun simctl terminate "$UDID" ae.barq.football 2>/dev/null || true
fi
xcrun simctl spawn "$UDID" log stream --style compact --predicate 'subsystem == "ae.barq.splash"' > "out/$MODE-timing.log" 2>&1 &
LOG=$!
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "out/$MODE-launch-uncut.mp4" > "out/$MODE-recording.log" 2>&1 &
REC=$!
cleanup() { kill -INT "$REC" 2>/dev/null || true; wait "$REC" || true; kill "$LOG" 2>/dev/null || true; }
trap cleanup EXIT
sleep 2
# Quick capture includes the existing home screen, actual termination and relaunch.
if [[ "$MODE" == quick ]]; then
  xcrun simctl terminate "$UDID" ae.barq.football 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$UDID" ae.barq.football -lang ar
else
  xcrun simctl launch "$UDID" ae.barq.football -lang ar -resetOnboarding YES
fi
for i in $(seq 1 45); do
  if grep -q 'FINISH cinematic=' "out/$MODE-timing.log"; then break; fi
  sleep 1
done
sleep 4
xcrun simctl io "$UDID" screenshot "out/$MODE-destination.png"
grep -q 'FINISH cinematic=' "out/$MODE-timing.log"
# No cutting, encoding, scaling, speed changes or frame replacement.
