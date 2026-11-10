#!/bin/bash
set -euo pipefail
mkdir -p out
# Keep host graphics capabilities with the evidence; never infer GPU support
# from a runner label or confuse simulator boot time with app startup.
system_profiler SPDisplaysDataType -json > out/host-graphics.json
xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  ci/record-simulator-window.swift -o out/record-simulator-window \
  > out/window-capture-build.log 2>&1
open -a Simulator --args -CurrentDeviceUDID "$UDID"
xcrun simctl terminate "$UDID" ae.barq.football 2>/dev/null || true
rm -f out/window-capture.stop out/window-launch-uncut.mp4.ready
xcrun simctl spawn "$UDID" log stream --style compact --predicate 'subsystem == "ae.barq.splash"' > out/window-timing.log 2>&1 &
LOG=$!
out/record-simulator-window out/window-launch-uncut.mp4 out/window-capture.stop > out/window-capture.log 2>&1 &
REC=$!
cleanup() {
  touch out/window-capture.stop
  wait "$REC" || true
  kill "$LOG" 2>/dev/null || true
}
trap cleanup EXIT
for i in $(seq 1 100); do
  if [[ -f out/window-launch-uncut.mp4.ready ]]; then break; fi
  if ! kill -0 "$REC" 2>/dev/null; then
    wait "$REC"
    exit 1
  fi
  sleep 0.2
done
test -f out/window-launch-uncut.mp4.ready
sleep 1
python3 ci/launch-measured.py out/window-timing.log window -lang ar
sleep 4
touch out/window-capture.stop
wait "$REC"
kill "$LOG" 2>/dev/null || true
trap - EXIT
ffprobe -v error -show_streams -show_format -of json out/window-launch-uncut.mp4 > out/window-capture-metadata.json
# The MP4 is ScreenCaptureKit's original output, with original timestamps.
# No interpolation, repeated-frame synthesis, speed changes, or replacement.
