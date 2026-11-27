#!/bin/bash
set -euo pipefail
mkdir -p out
# A separate real process launch using simctl's native HEVC encoder.
# This diagnoses capture-path differences; it never converts the H.264 evidence.
xcrun simctl terminate "$UDID" ae.barq.football 2>/dev/null || true
xcrun simctl spawn "$UDID" log stream --style compact --predicate 'subsystem == "ae.barq.splash"' > out/hevc-timing.log 2>&1 &
LOG=$!
xcrun simctl io "$UDID" recordVideo --codec=hevc --force out/hevc-launch-uncut.mp4 > out/hevc-recording.log 2>&1 &
REC=$!
cleanup() {
  kill -INT "$REC" 2>/dev/null || true
  wait "$REC" || true
  kill "$LOG" 2>/dev/null || true
}
trap cleanup EXIT
for i in $(seq 1 90); do
  kill -0 "$REC"
  if grep -q 'Recording started' out/hevc-recording.log; then break; fi
  sleep 1
done
grep -q 'Recording started' out/hevc-recording.log
sleep 1
python3 ci/launch-measured.py out/hevc-timing.log hevc -lang ar
sleep 4
cleanup
trap - EXIT
ffprobe -v error -show_streams -show_format -of json out/hevc-launch-uncut.mp4 > out/hevc-capture-metadata.json
