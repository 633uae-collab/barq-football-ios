#!/usr/bin/env python3
"""Reject sustained black viewport intervals in the original cold-launch video.

This supplements callback timing; it does not certify smoothness or identify the
first presented logo frame. The recording must start on the booted SpringBoard.
The status/home-indicator regions are excluded. No output video is modified.
"""
import re
import subprocess
import sys

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
