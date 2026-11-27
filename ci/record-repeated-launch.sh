#!/bin/bash
set -euo pipefail
# Five real process restarts, in one original recording, with saved onboarding
# and normal networking. No reinstallation, test bypass, cuts or speed changes.
mkdir -p out
open -a Simulator --args -CurrentDeviceUDID "$UDID" || true
caffeinate -d -i -u -t 180 </dev/null >/tmp/fotiq-capture-awake.log 2>&1 &
xcrun simctl terminate "$UDID" ae.barq.football 2>/dev/null || true
xcrun simctl spawn "$UDID" log stream --style compact --predicate 'subsystem == "ae.barq.splash"' > out/repeated-timing.log 2>&1 &
LOG=$!
xcrun simctl io "$UDID" recordVideo --codec=h264 --force out/repeated-launches-uncut.mp4 > out/repeated-recording.log 2>&1 &
REC=$!
cleanup() { kill -INT "$REC" 2>/dev/null || true; wait "$REC" || true; kill "$LOG" 2>/dev/null || true; }
trap cleanup EXIT
for attempt in $(seq 1 90); do
  kill -0 "$REC" || exit 1
  if grep -q 'Recording started' out/repeated-recording.log; then break; fi
  sleep 1
done
grep -q 'Recording started' out/repeated-recording.log
for cycle in $(seq 1 5); do
  xcrun simctl terminate "$UDID" ae.barq.football 2>/dev/null || true
  sleep 1
  printf 'REOPEN cycle=%s\n' "$cycle" >> out/repeated-cycles.log
  python3 ci/launch-measured.py out/repeated-timing.log "repeat-$cycle" -lang ar
  for attempt in $(seq 1 45); do
    count=$(grep -c 'FINISH firstLaunch=false' out/repeated-timing.log || true)
    if [[ "$count" -ge "$cycle" ]]; then break; fi
    sleep 1
  done
  [[ "$count" -eq "$cycle" ]]
  # Keep each revealed destination visible before the next process restart.
  sleep 1
done
xcrun simctl io "$UDID" screenshot out/repeated-final-destination.png
sleep 2
cleanup
trap - EXIT
python3 - <<'PY'
from pathlib import Path
import re
text = Path('out/repeated-timing.log').read_text()
rows = re.findall(r'BARQ\[(\d+):.*FINISH firstLaunch=false', text)
assert len(rows) == 5 and len(set(rows)) == 5, 'Five distinct completed-user process restarts are required'
assert 'FINISH firstLaunch=true' not in text, 'Repeated launches must retain saved onboarding'
print('Recorded five distinct process restarts without changing onboarding or networking')
PY
