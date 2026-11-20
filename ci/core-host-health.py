#!/usr/bin/env python3
"""Lightweight host progress, distinct from the app's MainActor heartbeat."""
import datetime
import json
import pathlib
import subprocess
import sys
import time

output = pathlib.Path(sys.argv[1])
previous = time.monotonic()
while True:
    now = time.monotonic()
    row = {"utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
           "hostGapMs": round((now - previous) * 1000)}
    previous = now
    try:
        result = subprocess.run(["ps", "-axo", "pid,stat,pcpu,rss,comm"],
                                capture_output=True, text=True, timeout=2, check=True)
        row["processColumns"] = "pid state cpuPercent rssKiB executable"
        # Match the executable, not every process under /CoreSimulator/.
        names = {"BARQ", "BARQUITests-Runner", "xcodebuild", "Simulator", "testmanagerd"}
        row["processes"] = [line.strip() for line in result.stdout.splitlines()
                            if pathlib.Path(line.split(maxsplit=4)[-1]).name in names]
    except (OSError, subprocess.SubprocessError) as error:
        row["healthReadError"] = type(error).__name__
    encoded = json.dumps(row)
    with output.open("a") as stream:
        stream.write(encoded + "\n")
    print("FOTIQ_HOST_HEALTH " + encoded, flush=True)
    time.sleep(5)

