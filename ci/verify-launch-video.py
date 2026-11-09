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
from statistics import pstdev

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
    'ffmpeg', '-v', 'fatal', '-i', sys.argv[1], '-vf', f'scale={width}:{height},format=gray',
    '-fps_mode', 'passthrough', '-f', 'rawvideo', '-pix_fmt', 'gray', '-'
])
stride = width * height
assert len(raw) == len(timestamps) * stride, 'Decoded frames must match original timestamps'
samples = []
for index, timestamp in enumerate(timestamps):
    frame = raw[index * stride:(index + 1) * stride]
    # Static launch field away from the logo; excludes status/home indicators.
    background = [frame[y * width + x] for y in range(52, 122) for x in range(8, 50)]
    if pstdev(background) > 12 or sum(background) / len(background) > 30:
        continue
    mark = [frame[y * width + x] for y in range(156, 192) for x in range(64, 96)]
    samples.append((timestamp, sum(value > 180 for value in mark)))
full_mark = max((count for _, count in samples), default=0)
full_times = [time for time, count in samples if full_mark and count >= full_mark * .95]
first_full = min(full_times, default=float('inf'))
partial = [(time, count) for time, count in samples
           if time > first_full and full_mark * .06 < count < full_mark * .94]
report = {
    'measurement': 'Original encoded MP4 frames; minimum phase visibility, not rendered-FPS certification',
    'encodedFrames': len(timestamps), 'fullMarkWhitePixelsAt160px': full_mark,
    'partialMarkFrames': [{'pts': time, 'whitePixels': count} for time, count in partial],
    'distinctPartialStates': len({count for _, count in partial}),
}
Path('out').mkdir(exist_ok=True)
Path('out/frame-review.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
if len(partial) < 6 or report['distinctPartialStates'] < 4:
    raise SystemExit('Recording omitted too much of the logo-erasure phase; do not approve visually')
