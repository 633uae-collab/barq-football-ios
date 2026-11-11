"""One bounded app-only sample at the first synthetic pending append, not entry."""
import datetime, json, os, pathlib, subprocess, time
out = pathlib.Path('out')
def event(**data):
    with (out/'send-sample-events.jsonl').open('a') as f:
        f.write(json.dumps(dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), **data))+'\n')
log = out/'transport.log'
end = time.monotonic()+240
while time.monotonic()<end:
    if log.exists() and 'message appended turns=4' in log.read_text(errors='replace'):
        break
    time.sleep(0.25)
else:
    event(stage='readiness', error='No fourth-turn append; no sample')
    raise SystemExit(1)
try:
    ps = subprocess.check_output(['ps','-axo','pid=,comm='], text=True, timeout=5)
except Exception as exc:
    event(stage='target', error=type(exc).__name__)
    raise SystemExit(1)
rows = [line.strip().split(None,1) for line in ps.splitlines() if line.strip()]
pids = [int(pid) for pid, path in rows if path.endswith('/BARQ.app/BARQ') and os.environ['UDID'] in path]
if len(pids)!=1:
    event(stage='target', error='Expected one app process on requested simulator', count=len(pids))
    raise SystemExit(1)
event(stage='sample', state='begin', pid=pids[0], udid=os.environ['UDID'], requestedSeconds=8, intervalMs=1, trigger='first synthetic pending append after three seeded long turns')
with (out/'send-sample-command.log').open('w') as f:
    r = subprocess.run(['python3','ci/run-core-command.py','25','sample',str(pids[0]),'8','1','-file',str(out/'send-app-sample.txt')],stdout=f,stderr=subprocess.STDOUT)
event(stage='sample', state='end', pid=pids[0], exit=r.returncode)
raise SystemExit(r.returncode)
