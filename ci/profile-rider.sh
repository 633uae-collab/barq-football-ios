#!/bin/bash
set -euo pipefail
mkdir -p out/trace
APP=$(find dd/Build/Products -name BARQ.app -path '*iphonesimulator*' | head -1)
APP=$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$APP")
for KIND in plain recorded; do
  xcrun simctl terminate "$UDID" ae.barq.football 2>/dev/null || true
  xcrun simctl spawn "$UDID" log stream --style compact --predicate 'subsystem == "ae.barq.splash"' > "out/trace/$KIND-timing.log" 2>&1 &
  LOG=$!
  REC=''
  cleanup() {
    if [[ -n "$REC" ]]; then kill -INT "$REC" 2>/dev/null || true; wait "$REC" || true; fi
    kill "$LOG" 2>/dev/null || true
  }
  trap cleanup EXIT
  if [[ "$KIND" == recorded ]]; then
    xcrun simctl io "$UDID" recordVideo --codec=h264 --force out/trace/profile-recorded-uncut.mp4 > out/trace/profile-recording.log 2>&1 &
    REC=$!
    for attempt in $(seq 1 60); do
      kill -0 "$REC"
      if grep -q 'Recording started' out/trace/profile-recording.log; then break; fi
      sleep 1
    done
    grep -q 'Recording started' out/trace/profile-recording.log
  fi
  # Identical fresh-onboarding route in both samples. Raw profiler traces and
  # the simultaneous unedited MP4 allow callback gaps to be correlated to stacks.
  # The original 12s recorded trace stopped sampling before motion on the slow
  # host. Extend capture, not the app timeline; retain all startup/hold cost.
  xcrun xctrace record --template 'Time Profiler' --device "$UDID" --time-limit 30s --output "out/trace/$KIND.trace" --launch -- "$APP" -lang ar -resetOnboarding YES > "out/trace/$KIND.log" 2>&1
  cleanup
  trap - EXIT
  xcrun xctrace export --input "out/trace/$KIND.trace" --toc > "out/trace/$KIND-toc.xml"
  for SCHEMA in time-profile potential-hangs os-signpost; do
    xcrun xctrace export --input "out/trace/$KIND.trace" --xpath "/trace-toc/run[@number='1']/data/table[@schema='$SCHEMA']" > "out/trace/$KIND-$SCHEMA.xml" 2>&1 || true
  done
done
