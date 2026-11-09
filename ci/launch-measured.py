#!/usr/bin/env python3
"""Measure simctl launch request -> observed app completion without changing app timing."""
import json, os, re, subprocess, sys, time
from pathlib import Path
log = Path(sys.argv[1])
label = sys.argv[2]
offset = log.stat().st_size if log.exists() else 0
start = time.monotonic()
command = ['xcrun', 'simctl', 'launch', os.environ['UDID'], 'ae.barq.football', *sys.argv[3:]]
p = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
returned = None
while time.monotonic() - start < 60:
    if p.poll() is not None and returned is None:
        returned = time.monotonic() - start
        if p.returncode != 0:
            raise SystemExit(p.stdout.read())
    with log.open(errors='replace') as f:
        f.seek(offset)
        observed = f.read()
        completed = re.search(r'BARQ\[(\d+):.*FINISH firstLaunch=(true|false).*mode=(premium|reduced)', observed)
    if completed:
        elapsed = time.monotonic() - start
        result = {'label': label, 'pid': int(completed[1]), 'firstLaunch': completed[2] == 'true', 'mode': completed[3],
                  'launchRequestToObservedFinishSeconds': elapsed,
                  'simctlReturnSeconds': returned, 'pollUncertaintySeconds': 0.01}
        with Path('out/startup-measurements.jsonl').open('a') as f:
            f.write(json.dumps(result) + '\n')
        print(json.dumps(result))
        p.communicate(timeout=10)
        if label != 'first' and result['firstLaunch']:
            raise SystemExit('Reopen recording requires completed real onboarding; observed firstLaunch=true')
        break
    time.sleep(0.01)
else:
    p.kill()
    raise SystemExit('No measured launch completion within 60 seconds')
