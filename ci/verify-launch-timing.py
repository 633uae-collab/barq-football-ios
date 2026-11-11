#!/usr/bin/env python3
"""Cadence acceptance is separate from visual acceptance and rendered FPS."""
from pathlib import Path
import json, re, sys
text = Path(sys.argv[1]).read_text(errors='replace')
finish = re.compile(r'FINISH firstLaunch=(true|false) elapsed=([0-9.]+) ready=(true|false) maxFrameGap=([0-9.]+) mode=(premium|reduced)')
stats = re.compile(r'FRAME_STATS samples=(\d+) mean=([0-9.]+) p95=([0-9.]+)')
rows = [dict(firstLaunch=m[1]=='true', elapsed=float(m[2]), ready=m[3]=='true', maxFrameGap=float(m[4]), mode=m[5]) for m in finish.finditer(text)]
cadence = [dict(samples=int(m[1]), meanGap=float(m[2]), p95Gap=float(m[3]), callbackFPS=1/float(m[2]) if float(m[2]) else 0) for m in stats.finditer(text)]
errors = []
if not any(r['firstLaunch'] for r in rows): errors.append('Missing first launch')
if not any(not r['firstLaunch'] for r in rows): errors.append('Missing completed-user relaunch')
if not any(r['mode']=='reduced' for r in rows): errors.append('Missing real Reduce Motion completion')
if len(rows) != len(cadence): errors.append('Missing cadence sample records')
for i, r in enumerate(rows):
    low, high = (1.8,2.0) if r['mode']=='premium' else (0.8,1.0)
    if not r['ready']: errors.append(f'{i}: destination not ready')
    if not low <= r['elapsed'] < high: errors.append(f'{i}: duration {r["elapsed"]:.4f}s outside {low}-{high}s')
    if r['maxFrameGap'] > .050: errors.append(f'{i}: frame gap {r["maxFrameGap"]:.4f}s exceeds 50ms')
for i, r in enumerate(cadence):
    # Reduced Motion may credit its 0.5 s static hold, leaving a 0.3 s fade.
    if r['samples'] < 12 or r['callbackFPS'] < 58 or r['p95Gap'] > .020:
        errors.append(f'{i}: unstable 60Hz callback cadence: {r}')
report = dict(measurement='Main-thread display-link callbacks; not proof of presented-frame FPS', launches=rows, cadence=cadence, failures=errors)
Path('out/timing-report.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
if errors: raise SystemExit(1)

