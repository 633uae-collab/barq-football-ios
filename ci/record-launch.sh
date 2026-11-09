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
xcrun simctl terminate "$UDID" ae.barq.football 2>/dev/null || true
xcrun simctl spawn "$UDID" log stream --style compact --predicate 'subsystem == "ae.barq.splash"' > "out/$MODE-timing.log" 2>&1 &
LOG=$!
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "out/$MODE-launch-uncut.mp4" > "out/$MODE-recording.log" 2>&1 &
REC=$!
cleanup() { kill -INT "$REC" 2>/dev/null || true; wait "$REC" || true; kill "$LOG" 2>/dev/null || true; }
trap cleanup EXIT
# Do not launch while simctl is still preparing its video encoder. A fixed
# two-second sleep produced a 0.995 s file containing only the destination.
for i in $(seq 1 90); do
  kill -0 "$REC" || exit 1
  if grep -q 'Recording started' "out/$MODE-recording.log"; then break; fi
  sleep 1
done
grep -q 'Recording started' "out/$MODE-recording.log"
sleep 2
if [[ "$MODE" == quick ]]; then
  # XCTest can terminate its app on completion. Bring the completed user's home
  # onscreen before recording the subsequent close/reopen, without changing prefs.
  python3 ci/launch-measured.py "out/$MODE-timing.log" "$MODE" -lang ar
  for i in $(seq 1 45); do
    if grep -q 'FINISH firstLaunch=false' "out/$MODE-timing.log"; then break; fi
    sleep 1
  done
  grep -q 'FINISH firstLaunch=false' "out/$MODE-timing.log"
  sleep 2
  cp "out/$MODE-timing.log" out/quick-first-opening-timing.log
  : > "out/$MODE-timing.log"
fi
# Recorder starts before warm launch so it receives changed frames before the
# subsequent termination. simctl otherwise omits the unchanged leading home frame.
if [[ "$MODE" == quick ]]; then
  xcrun simctl terminate "$UDID" ae.barq.football 2>/dev/null || true
  sleep 1
  python3 ci/launch-measured.py "out/$MODE-timing.log" "$MODE" -lang ar
else
  python3 ci/launch-measured.py "out/$MODE-timing.log" "$MODE" -lang ar -resetOnboarding YES
fi
for i in $(seq 1 45); do
  if grep -q 'FINISH firstLaunch=' "out/$MODE-timing.log"; then break; fi
  sleep 1
done
sleep 4
xcrun simctl io "$UDID" screenshot "out/$MODE-destination.png"
# Keep the fully revealed destination visible in the original recording; this
# changes recording duration only, never the app timeline or performance budget.
sleep 3
grep -q 'FINISH firstLaunch=' "out/$MODE-timing.log"
# No cutting, encoding, scaling, speed changes or frame replacement.

cleanup
trap - EXIT
# Reject recordings that missed startup instead of accepting log success alone.
ffprobe -v error -show_entries format=duration -of csv=p=0 "out/$MODE-launch-uncut.mp4" | python3 -c 'import sys; d=float(sys.stdin.read()); assert d >= 5, f"Recording missed launch: {d}s"'
