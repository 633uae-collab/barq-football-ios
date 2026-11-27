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
birth = None
launch_output = ''
while time.monotonic() - start < 60:
    if p.poll() is not None and returned is None:
        returned = time.monotonic() - start
        if p.returncode != 0:
            raise SystemExit(p.stdout.read())
        launch_output = p.stdout.read()
        pid = re.search(r'ae\.barq\.football:\s*(\d+)', launch_output)
        if pid:
            birth = float(subprocess.check_output(['out/process-birth', pid[1]], text=True).strip())
    with log.open(errors='replace') as f:
        f.seek(offset)
        observed = f.read()
        completed = re.search(r'BARQ\[(\d+):.*FINISH firstLaunch=(true|false).*mode=(premium|reduced)', observed)
    motion = re.search(r'MOTION committedToCompletion=([0-9.]+) creditedStaticHold=([0-9.]+) finishEpoch=([0-9.]+)', observed)
    if completed and motion and returned is not None:
        elapsed = time.monotonic() - start
        result = {'label': label, 'pid': int(completed[1]), 'firstLaunch': completed[2] == 'true', 'mode': completed[3],
                  'launchRequestToObservedFinishSeconds': elapsed,
                  'simctlReturnSeconds': returned, 'pollUncertaintySeconds': 0.01,
                  'processBirthEpoch': birth,
                  'processBirthToFinishSeconds': float(motion[3]) - birth if birth is not None else None,
                  'animatedTransactionSeconds': float(motion[1]), 'creditedStaticHoldSeconds': float(motion[2]),
                  'measurement': 'kernel process birth to app finish; excludes simulator boot and simctl request overhead'}
        if birth is None:
            raise SystemExit('Kernel process birth measurement missing; do not substitute simctl duration')
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

