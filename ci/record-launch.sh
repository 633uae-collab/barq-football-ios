#!/bin/bash
set -euo pipefail
MODE=${1:?first or quick}
[[ "$MODE" == first || "$MODE" == quick ]]
mkdir -p out
APP=$(find dd/Build/Products -name BARQ.app -path '*iphonesimulator*' | head -1)
if [[ "$MODE" == first ]]; then
  # A fresh simulator install also clears the OS launch-screen snapshot cache.
  xcrun simctl uninstall "$UDID" ae.barq.football 2>/dev/null || true
fi
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
if [[ "$MODE" == quick ]]; then
  # XCTest can terminate its app on completion. Bring the completed user's home
  # onscreen before recording the subsequent close/reopen, without changing prefs.
  xcrun simctl launch "$UDID" ae.barq.football -lang ar
  for i in $(seq 1 45); do
    if grep -q 'FINISH cinematic=false' "out/$MODE-timing.log"; then break; fi
    sleep 1
  done
  grep -q 'FINISH cinematic=false' "out/$MODE-timing.log"
  sleep 2
  : > "out/$MODE-timing.log"
fi
# Recorder starts before warm launch so it receives changed frames before the
# subsequent termination. simctl otherwise omits the unchanged leading home frame.
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
