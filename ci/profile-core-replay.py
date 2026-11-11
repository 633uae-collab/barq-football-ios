"""Bounded Instruments capture of synthetic replay after analyst readiness only."""
import json, os, pathlib, subprocess, time, datetime, sys
out = pathlib.Path('out')
log = out / 'replay.log'
wrapper = ['python3', 'ci/run-core-command.py']
def event(**data):
    with (out / 'instruments-events.jsonl').open('a') as f:
        f.write(json.dumps(dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), **data))+'\n')
def run(args, budget, name):
    event(stage=name, state='begin')
    with (out / (name+'.log')).open('w') as f:
        r = subprocess.run(wrapper+[str(budget)]+args, stdout=f, stderr=subprocess.STDOUT)
    event(stage=name, state='end', exit=r.returncode)
    return r.returncode
# Warm device discovery before the test owns a short-lived app PID.
# The prior run spent 39 s on help, then completed lookup after XCTest teardown.
if '--preflight' in sys.argv:
    pathlib.Path('/tmp/fotiq-core-profile-finished').unlink(missing_ok=True)
    help_exit = run(['xcrun','xctrace','help','record'],120,'instruments-help')
    device_exit = run(['xcrun','xctrace','list','devices'],120,'instruments-devices')
    devices = (out/'instruments-devices.log').read_text(errors='replace')
    if help_exit != 0 or device_exit != 0 or os.environ['UDID'] not in devices:
        event(stage='preflight', error='Profiler did not enumerate the selected simulator')
        raise SystemExit(1)
    event(stage='preflight', selectedDeviceEnumerated=True)
    raise SystemExit(0)
# Do not profile entry. XCTest emits this only after answer/source verification.
end = time.monotonic()+240
while time.monotonic()<end:
    if log.exists() and 'stage=input-start' in log.read_text(errors='replace'):
        break
    time.sleep(1)
else:
    event(stage='readiness', error='No analyst input marker; no capture')
    raise SystemExit(1)
try:
    ps = subprocess.check_output(['ps','-axo','pid=,comm='], text=True, timeout=5)
except Exception as e:
    event(stage='pid', error=type(e).__name__)
    raise SystemExit(1)
rows = [line.strip().split(None,1) for line in ps.splitlines() if line.strip()]
pids = [int(pid) for pid, path in rows if path.endswith('/BARQ.app/BARQ') and os.environ['UDID'] in path]
if len(pids)!=1:
    event(stage='pid', error='Expected one app executable on requested simulator', count=len(pids))
    raise SystemExit(1)
event(stage='target', pid=pids[0], udid=os.environ['UDID'], attachName='BARQ', fixture='synthetic-only')
record_exit = run(['xcrun','xctrace','record','--template','Time Profiler','--device',os.environ['UDID'],'--attach','BARQ','--time-limit','60s','--output','out/core-replay.trace','--no-prompt'],180,'instruments-record')
pathlib.Path('/tmp/fotiq-core-profile-finished').write_text(str(record_exit))
if record_exit != 0 or not (out/'core-replay.trace').exists():
    event(stage='capture', error='Instruments did not produce a successful recording')
    raise SystemExit(1)
if (out/'core-replay.trace').exists():
    run(['xcrun','xctrace','export','--input','out/core-replay.trace','--toc','--output','out/instruments-toc.xml'],60,'instruments-toc')
    run(['xcrun','xctrace','export','--input','out/core-replay.trace','--xpath','/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]','--output','out/instruments-samples.xml'],90,'instruments-samples')
