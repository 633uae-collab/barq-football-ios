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
from statistics import median

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
# The static original F occupies ~0.34 viewport widths in white pixels,
# with its separate green dot bringing the full silhouette to 0.38.
# Track the uncut departure from that measured size in the same short shot.
samples = []
for index, timestamp in enumerate(timestamps):
    frame = raw[index * stride:(index + 1) * stride]
    border = [frame[y * width + x] for y in (60, 90, 253, 281) for x in (4, 12, 147, 155)]
    if median(border) > 30:
        continue
    xs = [x for y in range(48, height - 48) for x in range(width) if frame[y * width + x] > 190]
    if xs:
        samples.append((timestamp, min(xs), max(xs), len(xs)))
full = [t for t, left, right, area in samples
        if 48 <= left <= 53 and 100 <= right <= 109 and 900 < area < 3200]
if not full:
    raise SystemExit('Missing centered original-size launch mark')
# Static frames can span the OS launch screen and destination preparation.
# Anchor the motion window at the last matching static frame before growth.
start = next((t for t, left, right, area in samples
              if t > full[0] and right-left+1 >= 60 and area > 1700), None)
if start is None:
    raise SystemExit('The centered launch mark never enlarged')
static = max(t for t in full if t < start)
moving = [(t, right-left+1) for t,left,right,area in samples
          if static < t <= static + 3.0 and 60 <= right-left+1 < width-2 and area > 1700]
report = dict(encodedFrames=len(timestamps), centeredLogoPTS=static, enlargingMark=moving,
              distinctWidths=len(set(span for _,span in moving)))
Path('out/frame-review.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
if len(moving) < 6 or report['distinctWidths'] < 4:
    raise SystemExit('Insufficient distinct camera approach frames in the original recording')
