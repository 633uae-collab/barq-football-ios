#!/usr/bin/env python3
"""Reject sustained black viewport intervals in the original cold-launch video.

This supplements callback timing; it does not certify smoothness or identify the
first presented logo frame. The recording must start on the booted SpringBoard.
The status/home-indicator regions are excluded. No output video is modified.
"""
import re
import subprocess
import sys
import json
from pathlib import Path
from bisect import bisect_left
from math import hypot

if len(sys.argv) != 2:
    raise SystemExit("expected the original cold-launch MP4")
result = subprocess.run([
    "ffmpeg", "-hide_banner", "-nostdin", "-i", sys.argv[1],
    "-vf", "crop=iw*0.90:ih*0.76:iw*0.05:ih*0.12,blackdetect=d=0.25:pix_th=0.02:pic_th=0.995",
    "-an", "-f", "null", "-"
], capture_output=True, text=True, check=True)
intervals = re.findall(r"black_start:([0-9.]+) black_end:([0-9.]+) black_duration:([0-9.]+)", result.stderr)
for start, end, duration in intervals:
    print(f"black viewport: {start}s to {end}s, duration={duration}s")
if intervals:
    raise SystemExit("launch video failed: sustained black viewport; inspect original recording")
print("No >=250ms near-black viewport interval detected; visual review is still required.")

# A valid file can still omit the entire Core Animation interval: run 42707577250
# had only 34 encoded frames in 23.6 s and no partially erased mark. Inspect the
# actual encoded frames (never interpolate/duplicate them to manufacture 60 fps).
metadata = json.loads(subprocess.check_output([
    'ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_frames',
    '-show_entries', 'frame=best_effort_timestamp_time', '-of', 'json', sys.argv[1]
]))
timestamps = [float(f['best_effort_timestamp_time']) for f in metadata['frames']]
width, height = 160, 348
raw = subprocess.check_output([
    'ffmpeg', '-v', 'fatal', '-i', sys.argv[1], '-vf', f'scale={width}:{height}:flags=area',
    '-fps_mode', 'passthrough', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'
])
stride = width * height * 3
assert len(raw) == len(timestamps) * stride, 'Decoded frames must match original timestamps'
# A full mark and a uniformly navy surrounding field anchor the sequence.
# Keep erasure frames from a single opening even in a multi-launch recording.
groups = []
active = None
for index, time in enumerate(timestamps):
    frame = memoryview(raw)[index * stride:(index + 1) * stride]
    def rgb(x, y):
        i = 3 * (y * width + x)
        return tuple(frame[i:i+3])
    field = all(max(rgb(x, y)) < 35 for x in (12, 147) for y in (62, 272))
    count = sum(min(rgb(x, y)) > 180 for x in range(48, 112) for y in range(137, 211))
    if field and 1800 <= count <= 2000 and rgb(101, 177)[1] - rgb(101, 177)[0] > 100:
        if active is None or time - active['lastFull'] > 2:
            active = {'lastFull': time, 'peak': count, 'partial': [], 'disk': []}
            groups.append(active)
        active['lastFull'] = time
        active['peak'] = max(active['peak'], count)
    elif active is not None and time - active['lastFull'] < 0.8:
        if field and active['peak'] * .06 < count < active['peak'] * .94:
            active['partial'].append((time, count))
        if active['partial'] and .25 < time - active['lastFull'] < .75:
            # Compare the current frame to the actual settled destination from this launch.
            # A blank dark patch on a fully visible Home screen is not a contracting disk.
            final_index = min(len(timestamps) - 1, bisect_left(timestamps, active['lastFull'] + 1.5))
            end_frame = memoryview(raw)[final_index * stride:(final_index + 1) * stride]
            mid = rgb(80,174)
            if max(mid) > 42:
                continue
            hidden, revealed = [], []
            for y in range(32, 317, 5):
                for x in range(5, 157, 5):
                    offset = (y * width + x) * 3
                    final = end_frame[offset:offset + 3]
                    now = rgb(x, y)
                    if sum(abs(a-b) for a,b in zip(final, mid)) < 58:
                        continue
                    distance = hypot(x - 79.5, y - 173.5)
                    if max(abs(a-b) for a,b in zip(now, mid)) < 7:
                        hidden.append(distance)
                    elif sum(abs(a-b) for a,b in zip(now, final)) < 42:
                        revealed.append(distance)
            # Both parts of the destination must contain recognizable detail.
            if len(hidden) >= 12 and len(revealed) >= 12:
                hidden.sort()
                revealed.sort()
                if hidden[int(.9 * len(hidden))] < revealed[int(.1 * len(revealed))]:
                    active['disk'].append(time)
partial = groups[-1]['partial'] if groups else []
disk = groups[-1]['disk'] if groups else []
report = {
    'measurement': 'Original encoded MP4 frames; minimum phase visibility, not rendered-FPS certification',
    'encodedFrames': len(timestamps), 'detectedFullMarks': len(groups), 'contractingDiskPTS': disk,
    'partialMarkFrames': [{'pts': time, 'whitePixels': count} for time, count in partial],
    'distinctPartialStates': len({count for _, count in partial}),
}
Path('out').mkdir(exist_ok=True)
Path('out', Path(sys.argv[1]).stem + '-frame-review.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
if not disk:
    raise SystemExit('No sampled central disk with revealed destination on both sides')
if len(partial) < 6 or report['distinctPartialStates'] < 4:
    raise SystemExit('Recording omitted too much of the logo-erasure phase; do not approve visually')
