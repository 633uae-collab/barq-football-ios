"""Compare stock and newly created CI devices. No application install or launch."""
import datetime
import json
import pathlib
import subprocess
import sys
import time
import uuid

OUT = pathlib.Path('out/boot-isolation')
OUT.mkdir(parents=True, exist_ok=True)
results = []

def command(label, seconds, *args):
    start = time.monotonic()
    with (OUT / (label + '.stdout')).open('w') as stdout, (OUT / (label + '.stderr')).open('w') as stderr:
        result = subprocess.run([sys.executable, 'ci/run-core-command.py', str(seconds), *args], stdout=stdout, stderr=stderr)
    row = dict(label=label, exitCode=result.returncode, durationSeconds=round(time.monotonic()-start, 3), utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    results.append(row)
    (OUT / 'results.json').write_text(json.dumps(results, indent=2))
    print(json.dumps(row), flush=True)
    return result.returncode

def diagnostics(label):
    # Fresh hosted machine only. No process arguments, application data or network requests.
    command(label+'-processes', 10, 'ps', '-axo', 'pid,ppid,state,pcpu,rss,comm')
    command(label+'-system-log', 20, '/usr/bin/log', 'show', '--last', '3m', '--style', 'compact', '--predicate', 'process == "simdiskimaged" OR process == "SimulatorTrampoline" OR process == "CoreSimulatorService"')

if command('devices', 120, 'xcrun', 'simctl', 'list', 'devices', 'available', '-j'):
    diagnostics('discovery-failed')
    sys.exit(1)
devices=json.loads((OUT/'devices.stdout').read_text())['devices']
choices=[(runtime, device) for runtime, rows in devices.items() if runtime.endswith('iOS-26-2') for device in rows if device['name']=='iPhone 17 Pro']
if len(choices)!=1:
    raise RuntimeError('Expected exactly one stock iPhone 17 Pro / iOS 26.2')
runtime, stock=choices[0]
if command('types', 30, 'xcrun', 'simctl', 'list', 'devicetypes', '-j'):
    sys.exit(1)
types=json.loads((OUT/'types.stdout').read_text())['devicetypes']
device_type=next(t['identifier'] for t in types if t['name']=='iPhone 17 Pro')
command('stock-boot', 30, 'xcrun', 'simctl', 'boot', stock['udid'])
stock_result=command('stock-readiness', 120, 'xcrun', 'simctl', 'bootstatus', stock['udid'], '-b')
diagnostics('stock')
# Prevent simultaneous simulator boot load. Do not erase or delete any device.
if command('stock-shutdown', 30, 'xcrun', 'simctl', 'shutdown', stock['udid']):
    sys.exit(1)
if command('fresh-create', 30, 'xcrun', 'simctl', 'create', 'FOTIQ-Core-Diagnostic-'+str(uuid.uuid4()), device_type, runtime):
    sys.exit(1)
fresh=(OUT/'fresh-create.stdout').read_text().strip()
uuid.UUID(fresh)
(OUT/'device-comparison.json').write_text(json.dumps(dict(runtime=runtime, deviceType=device_type, stock=stock['udid'], fresh=fresh, order=['stock','fresh'], applicationLaunched=False),indent=2))
command('fresh-boot', 30, 'xcrun', 'simctl', 'boot', fresh)
fresh_result=command('fresh-readiness', 120, 'xcrun', 'simctl', 'bootstatus', fresh, '-b')
diagnostics('fresh')
command('fresh-shutdown', 30, 'xcrun', 'simctl', 'shutdown', fresh)
# Both must complete; this status is environment diagnostics, never app acceptance.
sys.exit(1 if stock_result or fresh_result else 0)
